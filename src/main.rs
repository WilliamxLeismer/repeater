use clap::Parser;

mod create;
pub(crate) mod utils;

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
enum Args {
    /// Drill cards
    Drill {
        /// Path to the collection directory. By default, the current working directory is used.
        directory: Option<String>,
        /// Maximum number of cards to drill in a session. By default, all cards due today are drilled.
        #[arg(long)]
        card_limit: Option<usize>,
        /// Maximum number of new cards to drill in a session.
        #[arg(long)]
        new_card_limit: Option<usize>,
    },
    /// Create or append to a card
    Create {
        /// Card path
        card_path: String,
    },
}

fn main() {
    let args = Args::parse();
    match args {
        Args::Drill { .. } => todo!(),
        Args::Create { card_path } => {
            if let Err(err) = create::run(card_path) {
                eprintln!("error: {err}");
            }
        }
    }
}
