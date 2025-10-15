我来为程序添加 cron 支持，这样可以根据 cron 表达式来执行更新，而不是固定的时间间隔。

## 1. 更新 Cargo.toml

```toml
[package]
name = "cloudflare-ddns"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.0", features = ["full"] }
reqwest = { version = "0.11", features = ["json"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
config = "0.13"
anyhow = "1.0"
log = "0.4"
env_logger = "0.10"
cron = "0.12"
chrono = { version = "0.4", features = ["serde"] }
```

## 2. 更新主程序 src/main.rs

```rust
use anyhow::Result;
use config::{Config, Environment, File};
use log::{info, error, warn, debug};
use serde::Deserialize;
use std::time::Duration;
use tokio::time::sleep;
use cron::Schedule;
use chrono::{Utc, DateTime};
use std::str::FromStr;

#[derive(Debug, Deserialize)]
struct AppConfig {
    // 支持两种调度方式：cron 表达式或固定间隔
    update_interval: Option<u64>,
    cron_schedule: Option<String>,
    
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
    
    // 立即执行一次
    #[serde(default = "default_run_on_start")]
    run_on_start: bool,
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

fn default_run_on_start() -> bool {
    true
}

impl AppConfig {
    fn new() -> Result<Self> {
        let mut cfg = Config::builder();

        // 设置默认值
        cfg = cfg.set_default("dns_record_type", "A")?;
        cfg = cfg.set_default("proxy", false)?;
        cfg = cfg.set_default("ttl", 120)?;
        cfg = cfg.set_default("run_on_start", true)?;

        // 从可选的 env 文件加载
        if let Ok(env_file) = std::env::var("ENV_FILE") {
            cfg = cfg.add_source(File::with_name(&env_file).required(false));
        }

        // 从环境变量加载
        cfg = cfg.add_source(
            Environment::with_prefix("CF")
                .prefix_separator("_")
                .ignore_empty(true)
                .try_parsing(true)
        );

        let config = cfg.build()?;
        let app_config: AppConfig = config.try_deserialize()?;
        
        // 验证调度配置
        if app_config.update_interval.is_none() && app_config.cron_schedule.is_none() {
            return Err(anyhow::anyhow!("Either update_interval or cron_schedule must be specified"));
        }
        
        if app_config.update_interval.is_some() && app_config.cron_schedule.is_some() {
            warn!("Both update_interval and cron_schedule are specified, using cron_schedule");
        }
        
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
    
    // 获取调度模式
    fn get_schedule_mode(&self) -> ScheduleMode {
        if let Some(cron_expr) = &self.cron_schedule {
            ScheduleMode::Cron(cron_expr.clone())
        } else if let Some(interval) = self.update_interval {
            ScheduleMode::Interval(interval)
        } else {
            // 这不应该发生，因为构造函数已经验证过
            ScheduleMode::Interval(300) // 默认5分钟
        }
    }
}

#[derive(Debug)]
enum ScheduleMode {
    Interval(u64),
    Cron(String),
}

impl ScheduleMode {
    fn description(&self) -> String {
        match self {
            ScheduleMode::Interval(secs) => format!("every {} seconds", secs),
            ScheduleMode::Cron(expr) => format!("cron schedule '{}'", expr),
        }
    }
    
    async fn wait_until_next(&self) {
        match self {
            ScheduleMode::Interval(secs) => {
                sleep(Duration::from_secs(*secs)).await;
            }
            ScheduleMode::Cron(expr) => {
                if let Ok(schedule) = Schedule::from_str(expr) {
                    let now = Utc::now();
                    if let Some(next) = schedule.upcoming(Utc).next() {
                        let duration_until_next = next - now;
                        if duration_until_next.num_seconds() > 0 {
                            info!("⏰ Next update scheduled at: {}", next);
                            sleep(Duration::from_secs(duration_until_next.num_seconds() as u64)).await;
                        } else {
                            // 如果下一个执行时间已经过去，等待1秒后重新计算
                            sleep(Duration::from_secs(1)).await;
                        }
                    } else {
                        // 没有找到下一个执行时间，使用默认间隔
                        warn!("⚠️ Could not calculate next cron execution, using 60s fallback");
                        sleep(Duration::from_secs(60)).await;
                    }
                } else {
                    // cron 表达式解析失败，使用默认间隔
                    warn!("⚠️ Invalid cron expression, using 60s fallback");
                    sleep(Duration::from_secs(60)).await;
                }
            }
        }
    }
}

struct CloudflareClient {
    client: reqwest::Client,
}

impl CloudflareClient {
    fn new() -> Self {
        Self {
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(30))
                .build()
                .unwrap(),
        }
    }

    async fn get_current_ip(&self, record_type: &str) -> Result<String> {
        let service = match record_type {
            "AAAA" => "https://api6.ipify.org",
            _ => "https://api.ipify.org",
        };

        let response = self.client
            .get(service)
            .send()
            .await?
            .text()
            .await?;
        Ok(response)
    }

    async fn get_existing_record_id(
        &self,
        zone_id: &str,
        record_name: &str,
        record_type: &str,
        api_token: &str,
    ) -> Result<Option<String>> {
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

        let records: serde_json::Value = response.json().await?;
        
        if records["success"].as_bool() != Some(true) {
            let errors = records["errors"].to_string();
            return Err(anyhow::anyhow!("Cloudflare API error: {}", errors));
        }
        
        if let Some(records_array) = records["result"].as_array() {
            if let Some(record) = records_array.first() {
                if let Some(record_id) = record["id"].as_str() {
                    return Ok(Some(record_id.to_string()));
                }
            }
        }

        Ok(None)
    }

    async fn update_dns_record(
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

        if let Some(record_id) = self.get_existing_record_id(zone_id, record_name, record_type, api_token).await? {
            // 更新现有记录
            let update_url = format!("{}/{}", url, record_id);
            let update_data = serde_json::json!({
                "type": record_type,
                "name": record_name,
                "content": ip,
                "ttl": ttl,
                "proxied": proxy
            });

            let response = self.client
                .put(&update_url)
                .header("Authorization", format!("Bearer {}", api_token))
                .header("Content-Type", "application/json")
                .json(&update_data)
                .send()
                .await?;

            let result: serde_json::Value = response.json().await?;
            
            if result["success"].as_bool() == Some(true) {
                info!("✅ Successfully updated DNS record: {} -> {}", record_name, ip);
            } else {
                let errors = result["errors"].to_string();
                error!("❌ Failed to update DNS record {}: {}", record_name, errors);
                return Err(anyhow::anyhow!("Cloudflare API error: {}", errors));
            }
        } else {
            // 创建新记录
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
                info!("✅ Successfully created DNS record: {} -> {}", record_name, ip);
            } else {
                let errors = result["errors"].to_string();
                error!("❌ Failed to create DNS record {}: {}", record_name, errors);
                return Err(anyhow::anyhow!("Cloudflare API error: {}", errors));
            }
        }

        Ok(())
    }
}

async fn run_ddns_update(client: &CloudflareClient, config: &AppConfig) -> Result<()> {
    let current_ip = match client.get_current_ip(&config.dns_record_type).await {
        Ok(ip) => ip,
        Err(e) => {
            error!("❌ Failed to get current IP: {}", e);
            return Err(e);
        }
    };
    
    info!("🌐 Current public IP: {}", current_ip);

    let domain_names = config.get_domain_names();
    
    if domain_names.is_empty() {
        warn!("⚠️ No domain names configured");
        return Ok(());
    }

    info!("📝 Processing {} domain(s): {:?}", domain_names.len(), domain_names);

    let mut all_success = true;
    
    for domain_name in domain_names {
        info!("🔄 Updating DNS record for: {}", domain_name);
        match client.update_dns_record(
            &config.cf_zone_id,
            &domain_name,
            &config.dns_record_type,
            &config.cf_api_token,
            &current_ip,
            config.ttl,
            config.proxy,
        ).await {
            Ok(()) => {
                info!("✅ Successfully processed domain: {}", domain_name);
            }
            Err(e) => {
                error!("❌ Error updating domain {}: {}", domain_name, e);
                all_success = false;
            }
        }
    }

    if all_success {
        Ok(())
    } else {
        Err(anyhow::anyhow!("Some domain updates failed"))
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    
    let config = match AppConfig::new() {
        Ok(config) => config,
        Err(e) => {
            eprintln!("❌ Failed to load configuration: {}", e);
            eprintln!("💡 Please check your environment variables:");
            eprintln!("   - CF_API_TOKEN (required)");
            eprintln!("   - CF_ZONE_ID (required)"); 
            eprintln!("   - DNS_RECORD_NAME (required)");
            eprintln!("   - UPDATE_INTERVAL or CRON_SCHEDULE (one is required)");
            eprintln!("   - DNS_RECORD_TYPE (optional, defaults to A)");
            eprintln!("   - PROXY (optional, defaults to false)");
            eprintln!("   - TTL (optional, defaults to 120)");
            eprintln!("   - RUN_ON_START (optional, defaults to true)");
            eprintln!();
            eprintln!("📅 Cron examples:");
            eprintln!("   - Every 5 minutes: '0 */5 * * * *'");
            eprintln!("   - Every hour: '0 0 * * * *'");
            eprintln!("   - Every day at 2 AM: '0 0 2 * * *'");
            std::process::exit(1);
        }
    };
    
    info!("🚀 Starting Cloudflare DDNS client");
    
    let schedule_mode = config.get_schedule_mode();
    info!("⏰ Schedule: {}", schedule_mode.description());
    info!("🌍 Zone ID: {}", config.cf_zone_id);
    info!("📋 Record type: {}", config.dns_record_type);
    info!("🛡️ Proxy enabled: {}", config.proxy);
    info!("⏱️ TTL: {} seconds", config.ttl);
    info!("🎯 Run on start: {}", config.run_on_start);
    
    let domains = config.get_domain_names();
    info!("🎯 Monitoring {} domain(s): {:?}", domains.len(), domains);
    
    let client = CloudflareClient::new();
    
    // 如果配置了立即执行，则执行一次更新
    if config.run_on_start {
        info!("🔄 Performing initial DDNS update...");
        match run_ddns_update(&client, &config).await {
            Ok(()) => info!("✅ Initial update completed successfully"),
            Err(e) => error!("❌ Initial update failed: {}", e),
        }
    } else {
        info!("⏸️ Skipping initial update (RUN_ON_START=false)");
    }
    
    info!("🔄 Starting main update loop");
    
    // 主循环
    loop {
        schedule_mode.wait_until_next().await;
        
        info!("🔄 Scheduled DDNS update started");
        let start_time = Utc::now();
        
        match run_ddns_update(&client, &config).await {
            Ok(()) => {
                let duration = Utc::now() - start_time;
                info!("✅ Scheduled update completed in {}ms", duration.num_milliseconds());
            }
            Err(e) => {
                error!("❌ Scheduled update failed: {}", e);
            }
        }
    }
}
```

## 3. 环境变量文件示例

创建 `config.env`：
```bash
# Cloudflare API configuration
CF_API_TOKEN="J1Hcxx"  
CF_ZONE_ID="af8axx"      
DNS_RECORD_NAME="me.code.com,hn.code.com"    
DNS_RECORD_TYPE="A"             
PROXY=false
TTL=120

# 调度配置 - 使用其中一种方式
# 方式1: 固定时间间隔（秒）
# UPDATE_INTERVAL=300

# 方式2: Cron 表达式（推荐）
CRON_SCHEDULE="0 */5 * * * *"

# 是否在启动时立即执行一次
RUN_ON_START=true
```

## 4. 常用的 Cron 表达式示例

```bash
# 每5分钟执行一次
CRON_SCHEDULE="0 */5 * * * *"

# 每30分钟执行一次  
CRON_SCHEDULE="0 */30 * * * *"

# 每小时执行一次
CRON_SCHEDULE="0 0 * * * *"

# 每天凌晨2点执行
CRON_SCHEDULE="0 0 2 * * *"

# 每小时的0分和30分执行
CRON_SCHEDULE="0 0,30 * * * *"

# 工作日每10分钟执行
CRON_SCHEDULE="0 */10 * * * 1-5"
```

## 5. 构建和运行

### 构建 Docker 镜像：
```bash
docker build -t cloudflare-ddns .
```

### 运行容器：

**使用 cron 调度：**
```bash
docker run -d \
  --name ddns \
  --env-file config.env \
  cloudflare-ddns
```

**直接设置环境变量：**
```bash
docker run -d \
  --name ddns \
  -e CF_API_TOKEN="your_api_token" \
  -e CF_ZONE_ID="your_zone_id" \
  -e DNS_RECORD_NAME="me.code.com,hn.code.com" \
  -e CRON_SCHEDULE="0 */10 * * * *" \
  -e RUN_ON_START=true \
  cloudflare-ddns
```

## 6. 主要特性

1. **灵活的调度**：支持固定间隔和 cron 表达式两种方式
2. **cron 表达式**：使用标准的 6 字段 cron 格式（秒 分 时 日 月 星期）
3. **智能等待**：精确计算下一次执行时间
4. **启动控制**：可选择是否在启动时立即执行
5. **详细的日志**：显示下一次执行时间和执行耗时
6. **错误恢复**：cron 解析失败时自动回退到安全间隔

现在你可以使用更灵活的 cron 表达式来控制 DDNS 更新的频率，比如在特定时间执行，或者按照复杂的模式执行。