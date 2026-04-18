use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::fs::{File, OpenOptions};
use std::io::{BufRead, Error, Read, Write};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use std::{env, io, thread};
use warp::{Filter, Reply};

const LISTEN_PORT: u16 = 47890;

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct StartParams {
    pub path: String,
    pub arg: String,
}

fn sha256_file(path: &str) -> Result<String, Error> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0; 4096];

    loop {
        let bytes_read = file.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}

static LOGS: Lazy<Arc<Mutex<VecDeque<String>>>> =
    Lazy::new(|| Arc::new(Mutex::new(VecDeque::with_capacity(500))));
static PROCESS: Lazy<Arc<Mutex<Option<std::process::Child>>>> =
    Lazy::new(|| Arc::new(Mutex::new(None)));
static STDERR_LOG: Lazy<Arc<Mutex<Option<File>>>> = Lazy::new(|| {
    let path = env::temp_dir().join("flclash_stderr.log");
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .ok();
    Arc::new(Mutex::new(file))
});

fn start(start_params: StartParams) -> impl Reply {
    let sha256 = sha256_file(start_params.path.as_str()).unwrap_or("".to_string());
    if sha256 != env!("TOKEN") {
        return format!("The SHA256 hash of the program requesting execution is: {}. The helper program only allows execution of applications with the SHA256 hash: {}.", sha256,  env!("TOKEN"),);
    }
    stop();
    let mut process = PROCESS.lock().unwrap();
    match Command::new(&start_params.path)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .arg(&start_params.arg)
        .spawn()
    {
        Ok(child) => {
            let pid = child.id();
            *process = Some(child);
            log_message(format!(
                "[helper] core started pid={} path={} arg={}",
                pid, start_params.path, start_params.arg
            ));
            if let Some(ref mut child) = *process {
                if let Some(stdout) = child.stdout.take() {
                    spawn_log_reader(stdout, "stdout");
                }
                if let Some(stderr) = child.stderr.take() {
                    spawn_log_reader(stderr, "stderr");
                }
            }
            spawn_exit_monitor(pid);
            "".to_string()
        }
        Err(e) => {
            log_message(e.to_string());
            e.to_string()
        }
    }
}

fn stop() -> impl Reply {
    let mut process = PROCESS.lock().unwrap();
    if let Some(mut child) = process.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
    *process = None;
    "".to_string()
}

fn log_message(message: String) {
    let mut log_buffer = LOGS.lock().unwrap();
    if log_buffer.len() == 500 {
        log_buffer.pop_front();
    }
    log_buffer.push_back(format!("{}\n", message));
    drop(log_buffer);
    if let Ok(mut guard) = STDERR_LOG.lock() {
        if let Some(ref mut f) = *guard {
            let _ = writeln!(f, "{}", message);
            let _ = f.flush();
        }
    }
}

fn spawn_log_reader<R>(reader: R, stream: &'static str)
where
    R: Read + Send + 'static,
{
    let reader = io::BufReader::new(reader);
    thread::spawn(move || {
        for line in reader.lines() {
            match line {
                Ok(output) => {
                    log_message(format!("[helper:{}] {}", stream, output));
                }
                Err(err) => {
                    log_message(format!("[helper:{}] reader error: {}", stream, err));
                    break;
                }
            }
        }
        log_message(format!("[helper:{}] reader exited", stream));
    });
}

fn spawn_exit_monitor(pid: u32) {
    thread::spawn(move || loop {
        thread::sleep(Duration::from_millis(500));
        let mut process = PROCESS.lock().unwrap();
        let Some(child) = process.as_mut() else {
            break;
        };
        if child.id() != pid {
            break;
        }
        match child.try_wait() {
            Ok(Some(status)) => {
                log_message(format!(
                    "[helper] core exited pid={} success={} code={:?}",
                    pid,
                    status.success(),
                    status.code()
                ));
                *process = None;
                break;
            }
            Ok(None) => {}
            Err(err) => {
                log_message(format!("[helper] core wait failed pid={} err={}", pid, err));
                *process = None;
                break;
            }
        }
    });
}

fn get_logs() -> impl Reply {
    let log_buffer = LOGS.lock().unwrap();
    let value = log_buffer
        .iter()
        .cloned()
        .collect::<Vec<String>>()
        .join("\n");
    warp::reply::with_header(value, "Content-Type", "text/plain")
}

pub async fn run_service() -> anyhow::Result<()> {
    let api_ping = warp::get().and(warp::path("ping")).map(|| env!("TOKEN"));

    let api_start = warp::post()
        .and(warp::path("start"))
        .and(warp::body::json())
        .map(|start_params: StartParams| start(start_params));

    let api_stop = warp::post().and(warp::path("stop")).map(|| stop());

    let api_logs = warp::get().and(warp::path("logs")).map(|| get_logs());

    warp::serve(api_ping.or(api_start).or(api_stop).or(api_logs))
        .run(([127, 0, 0, 1], LISTEN_PORT))
        .await;

    Ok(())
}
