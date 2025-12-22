precommit:
    cargo fmt --all -- --check
    cargo clippy --fix --allow-dirty --allow-staged
    cargo machete
    cargo test

delete_db:
    rm "/Users/shaankhosla/Library/Application Support/repeat/cards.db"

create:
    cargo run -- create test.md

check:
    cargo run -- check test.md test_data/ science/

drill:
    cargo run -- drill test.md test_data/ science/
