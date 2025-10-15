//! Cloudflare DDNS Client
//!
//! A cross-platform dynamic DNS updater for Cloudflare.
//! Supports Windows, Linux, macOS on x86_64 and AArch64 architectures.
//!
//! # Features
//! - Multi-platform support (Windows, Linux, macOS)
//! - Multiple configuration sources (env file, environment variables, CLI args)
//! - Multiple domain support
//! - IPv4 and IPv6 support
//! - Automatic record creation
//! - Both one-time and continuous operation modes

use anyhow::Result;
use clap::Parser;
use config::{Config, Environment, File};
use log::{info, error, warn, debug};
use serde::Deserialize;
use std::time::Duration;
use tokio::time::sleep;
use chrono::{Utc, DateTime};
use std::collections::HashMap;

/// Platform information
#[derive(Debug)]
struct PlatformInfo {
    os: String,
    arch: String,
    family: String,
}

impl PlatformInfo {
    fn new() -> Self {
        Self {
            os: std::env::consts::OS.to_string(),
            arch: std::env::consts::ARCH.to_string(),
            family: std::env::consts::FAMILY.to_string(),
        }
    }
    
    fn display(&self) -> String {
        format!("{}-{}", self.os, self.arch)
    }
}

#[cfg(windows)]
/// Windows specific functionality
mod windows {
    use super::*;
    use winapi::um::winbase::GetComputerNameA;
    use std::ptr;
    use std::ffi::CString;
    
    pub fn get_host_identifier() -> Result<String> {
        // Windows: 使用计算机名作为标识
        unsafe {
            let mut buffer: [i8; 256] = [0; 256];
            let mut size = buffer.len() as u32;
            
            if GetComputerNameA(buffer.as_mut_ptr(), &mut size) != 0 {
                let hostname = CString::from_vec_unchecked(
                    buffer[..size as usize].iter().map(|&c| c as u8).collect()
                );
                Ok(hostname.to_string_lossy().into_owned())
            } else {
                Ok("unknown-windows-host".to_string())
            }
        }
    }
}

#[cfg(unix)]
/// Unix-like systems specific functionality (Linux, macOS, etc.)
mod unix {
    use super::*;
    use std::process::Command;
    
    pub fn get_host_identifier() -> Result<String> {
        // Unix: 使用 hostname 命令
        match Command::new("hostname").output() {
            Ok(output) if output.status.success() => {
                let hostname = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if hostname.is_empty() {
                    Ok("unknown-unix-host".to_string())
                } else {
                    Ok(hostname)
                }
            }
            _ => Ok("unknown-unix-host".to_string()),
        }
    }
}

#[cfg(not(any(windows, unix)))]
/// Fallback for other platforms
mod other {
    use super::*;
    
    pub fn get_host_identifier() -> Result<String> {
        Ok("unknown-platform".to_string())
    }
}

/// Get platform-specific host identifier
fn get_host_identifier() -> Result<String> {
    #[cfg(windows)]
    return windows::get_host_identifier();
    #[cfg(unix)]
    return unix::get_host_identifier();
    #[cfg(not(any(windows, unix)))]
    return other::get_host_identifier();
}

#[derive(Debug, Deserialize)]
struct AppConfig {
    // 调度配置
    update_interval: Option<u64>,
    
    // Cloudflare API 配置
    cf_api_token: String,
    cf_zone_id: String,
    
    // DNS 记录配置
    dns_record_name: String,
    #[serde(default = "default_record_type")]
    dns_record_type: String,
    #[serde(default = "default_proxy")]
    proxy: bool,
    #[serde(default = "default_ttl")]
    ttl: u32,
    
    // 网络配置
    network: Option<String>,
    
    // 平台特定配置
    #[serde(default)]
    platform_identifier: String,
}

#[derive(Parser, Debug)]
#[command(
    author,
    version,
    about = "Cross-platform Cloudflare DDNS client",
    long_about = "A dynamic DNS updater for Cloudflare that works on Windows, Linux, and macOS.\nSupports multiple domains and both IPv4 and IPv6 addresses."
)]
struct CliArgs {
    /// Cloudflare API token
    #[arg(long, env = "CF_API_TOKEN")]
    cf_api_token: Option<String>,
    
    /// Cloudflare zone ID
    #[arg(long, env = "CF_ZONE_ID")]
    cf_zone_id: Option<String>,
    
    /// DNS record name (multiple domains separated by commas)
    #[arg(long, env = "DNS_RECORD_NAME")]
    dns_record_name: Option<String>,
    
    /// DNS record type [default: A]
    #[arg(long, default_value = "A")]
    dns_record_type: Option<String>,
    
    /// Enable Cloudflare proxy [default: false]
    #[arg(long, default_value = "false")]
    proxy: bool,
    
    /// TTL in seconds [default: 120]
    #[arg(long, default_value = "120")]
    ttl: u32,
    
    /// Network identifier
    #[arg(long, env = "NETWORK")]
    network: Option<String>,
    
    /// Update interval in seconds [default: 300]
    #[arg(long)]
    update_interval: Option<u64>,
    
    /// Run once and exit
    #[arg(long, default_value = "false")]
    once: bool,
    
    /// Show platform information
    #[arg(long, default_value = "false")]
    show_platform: bool,
    
    /// Use RustLS instead of native TLS (may reduce binary size)
    #[arg(long, default_value = "false")]
    use_rustls: bool,
}

fn default_record_type() -> String {
    "A".to_string()
}

fn default_proxy() -> bool {
    false
}

fn default_ttl() -> u32 {
    120 // 2 minutes
}

impl AppConfig {
    fn new() -> Result<Self> {
        let platform = PlatformInfo::new();
        let host_identifier = get_host_identifier().unwrap_or_else(|_| "unknown".to_string());
        
        let mut cfg = Config::builder();

        // 设置默认值
        cfg = cfg.set_default("dns_record_type", "A")?;
        cfg = cfg.set_default("proxy", false)?;
        cfg = cfg.set_default("ttl", 120)?;
        cfg = cfg.set_default("platform_identifier", host_identifier)?;

        // 从可选的 env 文件加载
        if let Ok(env_file) = std::env::var("ENV_FILE") {
            cfg = cfg.add_source(File::with_name(&env_file).required(false));
        } else {
            // 尝试加载 .env 文件
            let _ = dotenvy::dotenv();
        }

        // 从环境变量加载
        cfg = cfg.add_source(
            Environment::with_prefix("CF")
                .prefix_separator("_")
                .ignore_empty(true)
                .try_parsing(true)
        );

        let config = cfg.build()?;
        let mut app_config: AppConfig = config.try_deserialize()?;
        
        // 应用命令行参数（覆盖环境变量和配置文件）
        let cli_args = CliArgs::parse();
        
        if cli_args.show_platform {
            println!("Platform: {}", platform.display());
            println!("OS: {}", platform.os);
            println!("Architecture: {}", platform.arch);
            println!("Family: {}", platform.family);
            std::process::exit(0);
        }
        
        if let Some(token) = cli_args.cf_api_token {
            app_config.cf_api_token = token;
        }
        if let Some(zone_id) = cli_args.cf_zone_id {
            app_config.cf_zone_id = zone_id;
        }
        if let Some(record_name) = cli_args.dns_record_name {
            app_config.dns_record_name = record_name;
        }
        if let Some(record_type) = cli_args.dns_record_type {
            app_config.dns_record_type = record_type;
        }
        if let Some(network) = cli_args.network {
            app_config.network = Some(network);
        }
        if let Some(interval) = cli_args.update_interval {
            app_config.update_interval = Some(interval);
        }
        
        app_config.proxy = cli_args.proxy;
        app_config.ttl = cli_args.ttl;
        
        Ok(app_config)
    }

    // 解析多个域名
    fn get_domain_names(&self) -> Vec<String> {
        self.dns_record_name
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect()
    }
    
    fn validate(&self) -> Result<()> {
        if self.cf_api_token.is_empty() {
            return Err(anyhow::anyhow!("CF_API_TOKEN must be set"));
        }
        if self.cf_zone_id.is_empty() {
            return Err(anyhow::anyhow!("CF_ZONE_ID must be set"));
        }
        if self.dns_record_name.is_empty() {
            return Err(anyhow::anyhow!("DNS_RECORD_NAME must be set"));
        }
        
        let domains = self.get_domain_names();
        if domains.is_empty() {
            return Err(anyhow::anyhow!("No valid domain names found in DNS_RECORD_NAME"));
        }
        
        if self.ttl < 1 || self.ttl > 86400 {
            return Err(anyhow::anyhow!("TTL must be between 1 and 86400 seconds"));
        }
        
        Ok(())
    }
}

// 其余代码保持不变...
// [之前的 CloudflareClient, info_step, info_status, update_domains, run_ddns_update 等函数]

struct CloudflareClient {
    client: reqwest::Client,
}

impl CloudflareClient {
    fn new(use_rustls: bool) -> Self {
        let client_builder = reqwest::Client::builder()
            .timeout(Duration::from_secs(30));
            
        // 根据平台和选择使用不同的 TLS 后端
        #[cfg(feature = "rustls")]
        let client_builder = if use_rustls {
            client_builder.use_rustls_tls()
        } else {
            client_builder
        };
        
        Self {
            client: client_builder.build().unwrap(),
        }
    }

    async fn get_public_ip(&self, record_type: &str) -> Result<String> {
        let services = match record_type {
            "AAAA" => vec![
                "https://api6.ipify.org",
                "https://ident.me",
                "https://ifconfig.me/ip",
            ],
            _ => vec![
                "https://api.ipify.org",
                "https://ident.me", 
                "https://ifconfig.me/ip",
            ],
        };
        
        for service in services {
            match self.client.get(service).timeout(Duration::from_secs(5)).send().await {
                Ok(response) => {
                    if response.status().is_success() {
                        let ip = response.text().await?.trim().to_string();
                        if !ip.is_empty() {
                            return Ok(ip);
                        }
                    }
                }
                Err(_) => continue,
            }
        }
        
        Err(anyhow::anyhow!("Unable to obtain public IP from any service"))
    }

    // 其余 CloudflareClient 方法保持不变...
    async fn get_dns_record(
        &self,
        zone_id: &str,
        record_name: &str,
        record_type: &str,
        api_token: &str,
    ) -> Result<Option<serde_json::Value>> {
        let url = format!(
            "https://api.cloudflare.com/client/v4/zones/{}/dns_records",
            zone_id
        );

        let response = self.client
            .get(&url)
            .header("Authorization", format!("Bearer {}", api_token))
            .query(&[("name", record_name), ("type", record_type)])
            .send()
            .await?;

        let result: serde_json::Value = response.json().await?;
        
        if result["success"].as_bool() != Some(true) {
            let errors = result["errors"].to_string();
            return Err(anyhow::anyhow!("Cloudflare API error: {}", errors));
        }
        
        if let Some(records_array) = result["result"].as_array() {
            if let Some(record) = records_array.first() {
                return Ok(Some(record.clone()));
            }
        }

        Ok(None)
    }

    async fn update_dns_record(
        &self,
        zone_id: &str,
        record_id: &str,
        record_name: &str,
        record_type: &str,
        api_token: &str,
        ip: &str,
        ttl: u32,
        proxy: bool,
    ) -> Result<()> {
        let url = format!(
            "https://api.cloudflare.com/client/v4/zones/{}/dns_records/{}",
            zone_id, record_id
        );

        let update_data = serde_json::json!({
            "type": record_type,
            "name": record_name,
            "content": ip,
            "ttl": ttl,
            "proxied": proxy
        });

        let response = self.client
            .put(&url)
            .header("Authorization", format!("Bearer {}", api_token))
            .header("Content-Type", "application/json")
            .json(&update_data)
            .send()
            .await?;

        let result: serde_json::Value = response.json().await?;
        
        if result["success"].as_bool() == Some(true) {
            info!("✅ Successfully updated DNS record: {} -> {}", record_name, ip);
            Ok(())
        } else {
            let errors = result["errors"].to_string();
            Err(anyhow::anyhow!("Cloudflare API error: {}", errors))
        }
    }

    async fn add_dns_record(
        &self,
        zone_id: &str,
        record_name: &str,
        record_type: &str,
        api_token: &str,
        ip: &str,
        ttl: u32,
        proxy: bool,
    ) -> Result<()> {
        let url = format!(
            "https://api.cloudflare.com/client/v4/zones/{}/dns_records",
            zone_id
        );

        let create_data = serde_json::json!({
            "type": record_type,
            "name": record_name,
            "content": ip,
            "ttl": ttl,
            "proxied": proxy
        });

        let response = self.client
            .post(&url)
            .header("Authorization", format!("Bearer {}", api_token))
            .header("Content-Type", "application/json")
            .json(&create_data)
            .send()
            .await?;

        let result: serde_json::Value = response.json().await?;
        
        if result["success"].as_bool() == Some(true) {
            info!("✅ Successfully added DNS record: {} -> {}", record_name, ip);
            Ok(())
        } else {
            let errors = result["errors"].to_string();
            Err(anyhow::anyhow!("Cloudflare API error: {}", errors))
        }
    }
}

fn get_time_now() -> String {
    Utc::now().format("%Y-%m-%d %H:%M:%S").to_string()
}

fn info_step(msg: &str, length: usize, fillchar: char) {
    let msg_len = msg.len();
    let fill_length = (length - msg_len + 2) / 2;
    let padding = fillchar.to_string().repeat(fill_length);
    let padded_msg = format!("{}{}{}{}", padding, fillchar, msg, fillchar);
    println!("{}", &padded_msg[..length.min(padded_msg.len())]);
}

fn info_status(msg_body: &str, status: u8) {
    let icon = match status {
        0 => "✅",
        1 => "❌", 
        _ => "ℹ️",
    };
    println!("{} {}", icon, msg_body);
}

async fn update_domains(client: &CloudflareClient, config: &AppConfig, current_ip: &str) -> Result<()> {
    let domain_names = config.get_domain_names();
    
    for domain in domain_names {
        let step_name = format!("get DNS record for {}", domain);
        info_step(&step_name, 60, '-');
        
        match client.get_dns_record(
            &config.cf_zone_id,
            &domain,
            &config.dns_record_type,
            &config.cf_api_token,
        ).await {
            Ok(Some(dns_record)) => {
                info_status(&format!("{} - DNS record {} found", get_time_now(), domain), 0);
                
                let record_ip = dns_record["content"].as_str().unwrap_or("");
                if record_ip != current_ip {
                    info_status(&format!("{} - IP change detected: Record IP {}, Current IP {} for {}", 
                        get_time_now(), record_ip, current_ip, domain), 0);
                    
                    let step_name = format!("update DNS record for {}", domain);
                    info_step(&step_name, 60, '-');
                    
                    let record_id = dns_record["id"].as_str().unwrap();
                    if let Err(e) = client.update_dns_record(
                        &config.cf_zone_id,
                        record_id,
                        &domain,
                        &config.dns_record_type,
                        &config.cf_api_token,
                        current_ip,
                        config.ttl,
                        config.proxy,
                    ).await {
                        error!("❌ Failed to update domain {}: {}", domain, e);
                    } else {
                        info_status(&format!("{} - DNS record {} updated to {}", get_time_now(), domain, current_ip), 0);
                    }
                } else {
                    info_status(&format!("{} - IP not changed ({}) for {}", get_time_now(), current_ip, domain), 0);
                }
            }
            Ok(None) => {
                info_status(&format!("{} - DNS record {} not found, attempting to add", get_time_now(), domain), 1);
                
                if let Err(e) = client.add_dns_record(
                    &config.cf_zone_id,
                    &domain,
                    &config.dns_record_type,
                    &config.cf_api_token,
                    current_ip,
                    config.ttl,
                    config.proxy,
                ).await {
                    error!("❌ Failed to add domain {}: {}", domain, e);
                } else {
                    info_status(&format!("{} - DNS record {} added successfully", get_time_now(), domain), 0);
                }
            }
            Err(e) => {
                error!("❌ Failed to get DNS record for {}: {}", domain, e);
            }
        }
    }
    
    Ok(())
}

async fn run_ddns_update(client: &CloudflareClient, config: &AppConfig) -> Result<()> {
    let step_name = "get public IP";
    info_step(step_name, 60, '-');
    
    let current_ip = match client.get_public_ip(&config.dns_record_type).await {
        Ok(ip) => {
            info_status(&format!("{} - Public IP address {}", get_time_now(), ip), 0);
            ip
        }
        Err(e) => {
            info_status(&format!("{} - Failed to get public IP address: {}", get_time_now(), e), 1);
            return Err(e);
        }
    };
    
    update_domains(client, config, &current_ip).await
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    
    let platform = PlatformInfo::new();
    info!("🚀 Starting Cloudflare DDNS Client on {}", platform.display());
    
    // 加载配置
    let config = match AppConfig::new() {
        Ok(config) => config,
        Err(e) => {
            eprintln!("❌ Failed to load configuration: {}", e);
            eprintln!("💡 Configuration sources:");
            eprintln!("   - .env file (optional)");
            eprintln!("   - Environment variables with CF_ prefix");
            eprintln!("   - Command line arguments");
            eprintln!();
            eprintln!("🔧 Required variables:");
            eprintln!("   - CF_API_TOKEN: Cloudflare API token");
            eprintln!("   - CF_ZONE_ID: Cloudflare zone ID");
            eprintln!("   - DNS_RECORD_NAME: Domain name(s) separated by commas");
            std::process::exit(1);
        }
    };
    
    // 验证配置
    if let Err(e) = config.validate() {
        eprintln!("❌ Configuration validation failed: {}", e);
        std::process::exit(1);
    }
    
    let cli_args = CliArgs::parse();
    
    // 显示配置信息
    info_step("Configuration", 60, '=');
    info_status(&format!("Platform: {}", platform.display()), 0);
    info_status(&format!("Zone ID: {}", config.cf_zone_id), 0);
    info_status(&format!("Record type: {}", config.dns_record_type), 0);
    info_status(&format!("Proxy enabled: {}", config.proxy), 0);
    info_status(&format!("TTL: {} seconds", config.ttl), 0);
    info_status(&format!("Host identifier: {}", config.platform_identifier), 0);
    if let Some(network) = &config.network {
        info_status(&format!("Network: {}", network), 0);
    }
    
    let domains = config.get_domain_names();
    info_status(&format!("Monitoring {} domain(s): {:?}", domains.len(), domains), 0);
    
    let client = CloudflareClient::new(cli_args.use_rustls);
    
    // 执行一次更新
    info_step("Initial DDNS Update", 60, '=');
    if let Err(e) = run_ddns_update(&client, &config).await {
        error!("❌ Initial update failed: {}", e);
    }
    
    // 如果指定了 --once 参数，只执行一次就退出
    if cli_args.once {
        info_step("Completed (one-time mode)", 60, '=');
        return Ok(());
    }
    
    // 持续运行模式
    let interval = config.update_interval.unwrap_or(300);
    info_step(&format!("Starting update loop ({}s interval)", interval), 60, '=');
    
    loop {
        sleep(Duration::from_secs(interval)).await;
        
        info_step("Scheduled Update", 60, '-');
        if let Err(e) = run_ddns_update(&client, &config).await {
            error!("❌ Scheduled update failed: {}", e);
        }
    }
}