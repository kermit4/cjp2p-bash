This implements some https://github.com/kermit4/cjp2p protocol.

messages handled:
- Content receive/send
- Peers receive/send
- PleaseSendContent receive/send
- PleaseSendPeers receive/send
- PleaseReturnThisMessage receive
- ReturnedMessage send


Unfortunately BASH's networking capability was limited so it needed some Rust to use the socket.  You could make the Rust part in many other languages easily if you prefer.

This might not be secure, it's a prototype for using BASH because I like BASH.  

It does not yet share peers or content.

It's fairly slow, topping out at 35Mbps on my Intel(R) Core(TM) i5-7200U CPU @ 2.50GHz

TODO
reply with Peers to PleaseSendPeers


The socket handler could be rewritten as just dropping packets into a dir as files, with the source host:ip.random and the BASH could do the same in an outgoing dir.  idk if that's any faster, but it would handle parallelism better, no single channel of bottleneck.  Also it'd fix deadlocks and races.

# todo

- fix deadlocking when rust is writing to the BASH but the BASH is writing to the rust
- consider the rare possibility of a race where the head -c 33 reads 33 but gets killed by the timeout before writing 33
