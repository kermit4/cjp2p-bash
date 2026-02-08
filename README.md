This implements the https://github.com/kermit4/cjp2p protocol.

Unfortunately BASH's networking capability was limited so it needed some Rust to use the socket.  You could make the Rust part in many other languages easily if you prefer.

This might not be secure, it's a prototype for using BASH because I like BASH.  

It does not yet share peers or content.

It's fairly slow, topping out at 35Mbps on my Intel(R) Core(TM) i5-7200U CPU @ 2.50GHz

TODO
reply with Peers to PleaseSendPeers
reply to PleaseSendContent
