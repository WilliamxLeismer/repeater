precommit:
    cargo fmt --all
    cargo clippy --fix --allow-dirty --allow-staged
    cargo machete
    cargo test
