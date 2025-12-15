use std::path::{Path, PathBuf};

use anyhow::{Result, anyhow};

pub fn validate_file(path: String) -> Result<PathBuf> {
    let card_path = path.trim();
    if card_path.is_empty() {
        return Err(anyhow!("Card path cannot be empty"));
    }
    let card_path = PathBuf::from(card_path);
    if card_path.is_dir() {
        return Err(anyhow!(
            "Card path cannot be a directory: {}",
            card_path.display()
        ));
    }

    if !is_markdown(&card_path) {
        return Err(anyhow!(
            "Card path must be a markdown file: {}",
            card_path.display()
        ));
    }

    Ok(card_path)
}
pub fn is_markdown(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| ext.eq_ignore_ascii_case("md"))
        .unwrap_or(false)
}
