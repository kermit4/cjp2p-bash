
debug:
	cargo build

release:
	cargo build --release

check:
	cargo check

test: release
	./cjp2p.bash  32M $$((1<<25))
