
debug:
	cargo build

release:
	cargo build --release

check:
	cargo check

test: release
	rm -rf cjp2p.bash.dir/incoming
	echo sha256sum cjp2p.bash.dir/incoming/5b6656f16181bc0689b583d02b8b8272a02049af3ba07715c4a6c08beef814c2
	sleep 2
	./cjp2p.bash  5b6656f16181bc0689b583d02b8b8272a02049af3ba07715c4a6c08beef814c2  $$((1<<23)) # 256M
