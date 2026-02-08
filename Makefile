
debug:
	cargo build

release:
	cargo build --release

check:
	cargo check

test: release
	./cjp2p.bash  cb407d7355bb63929d7f4b282684f5a2884a0c3fb73d56642455600569a6888b  $$((1<<28)) # 256M
