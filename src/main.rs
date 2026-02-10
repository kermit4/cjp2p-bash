//use base64::{engine::general_purpose, Engine as _};
use std::io::{Read, Write};
use std::os::fd::AsFd;
//use std::os::unix::io::FromRawFd;
//use std::os::fd::AsRawFd;
//use bitvec::prelude::*;
//use chrono::{Timelike, Utc};
use log::{debug, error, info, trace, warn};
//use serde::{Deserialize, Serialize};
//use serde_json::Value;
//use std::cmp;
//use sha2::{Digest, Sha256};
//use std::collections::{HashMap, HashSet};
//use std::convert::TryInto;
//use std::env;
//use std::fmt;
//use std::f64;
//use std::fs;
use std::fs::File;
//use std::fs::OpenOptions;
//use std::io::copy;
use std::net::{SocketAddr, UdpSocket};
//use std::os::unix::fs::FileExt;
//use std::path::Path;
//use rand::Rng;
//use std::str;
//use std::time::Duration;
//use std::time::{Duration, Instant};
//use std::vec;
use nix::sys::select::{select, FdSet};
//use nix::unistd::{close, read};
//use std::net::{SocketAddr, UdpSocket};

fn main() -> Result<(), std::io::Error> {
    env_logger::init();
    let socket = UdpSocket::bind("0.0.0.0:24256")?;
    socket.set_broadcast(true).ok();
    //  let mut args = env::args();
    //    args.next();
    //for v in args {
    //    info!("queing inbound file {:?}", v);
    //      InboundStates::new(&mut inbound_states, v.as_str());
    //    }
    let udp_fd = socket.as_fd();
    let mut buffer = [0; 0x10000];
    let stdin = std::io::stdin();
    let stdin_fd = stdin.as_fd();
    let mut stdout = File::create("/proc/self/fd/1").unwrap(); // there surpsingly does not appear to be a simple non-unsafe{} way to write to stdout without buffering, stdout is treated too specially in Rust (and no, just calling flush() does NOT do the same thing)
    loop {
        let mut read_fds = FdSet::new();
        read_fds.insert(udp_fd);
        read_fds.insert(stdin_fd);

        match select(
            None,
            &mut read_fds,
            None,
            None,
            None,
            // &mut (nix::sys::time::TimeVal::new(1, 0)),
        ) {
            Ok(n) => {
                debug!("select: {n}");
            }
            Err(e) => warn!("Error reading from stdin: {}", e),
        }

        if read_fds.contains(stdin_fd) {
            let mut line = String::new();
            match std::io::stdin().read_line(&mut line) {
                Ok(_) => (),
                Err(e) => panic!("Error reading line: {0} {1}", e,line)

            }
            debug!("line {0}: {1}",line.len(),line);
            let dst: SocketAddr; 
            match line.trim().parse::<SocketAddr>() {
                Ok(s) => dst = s,
                Err(e) => panic!("Error unwrapping addr: {0} {1}", e,line)}
            debug!("line:{line}");
            let mut line = String::new();
            std::io::stdin().read_line(&mut line).unwrap();
            debug!("line2:{line}");
            let bytes_to_read: usize = line.trim().parse().unwrap();
            let mut message = vec![0u8; bytes_to_read];
            let message_len = std::io::stdin()
                .read(&mut message[..bytes_to_read])
                .unwrap();
            assert!(message_len == bytes_to_read);
            socket.send_to(&message[..message_len], dst).ok();
        }

        if read_fds.contains(udp_fd) {
            match socket.recv_from(&mut buffer) {
                Ok((message_len, src)) => {
                    debug!("Received from {}: {:?}", src, &buffer[..message_len]);
                    info!("incoming message from {src}",);
                    //unsafe { let stdout = File::from_raw_fd(1); } // inconsistently, unbuffered writing to stdout is "unsafe" in rust, but not to any other file.
                    println!("{:25} {:6}", src,message_len);
                    std::io::stdout().flush().ok();
                    stdout.write(&buffer[0..message_len]).unwrap();
                }
                Err(e) => warn!("Error receiving UDP message: {}", e),
            }
        }
    }
}
