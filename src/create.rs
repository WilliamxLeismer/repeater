use crate::utils::validate_file;

use std::{
    fs::{self, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    time::Duration,
};

use anyhow::Result;
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind, KeyModifiers},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{
    Terminal,
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::Stylize,
    widgets::{Block, Borders, Paragraph, Wrap},
};

pub fn run(card_path: String) -> Result<()> {
    let card_path = validate_file(card_path)?;
    process_card(card_path)
}

fn process_card(card_path: PathBuf) -> Result<()> {
    let card_exists = card_path.is_file();
    if !card_exists {
        if !prompt_create(&card_path)? {
            println!("Aborting; card not created.");
            return Ok(());
        }
        if let Some(parent) = card_path.parent()
            && !parent.as_os_str().is_empty()
        {
            fs::create_dir_all(parent)?;
        }
    }

    match capture_card_text(&card_path.display().to_string())? {
        Some(body) if !body.trim().is_empty() => {
            append_to_card(&card_path, &body)?;
            println!("Card updated: {}", card_path.display());
        }
        Some(_) | None => {
            println!("No text captured; nothing written.");
        }
    }

    Ok(())
}

fn prompt_create(path: &Path) -> io::Result<bool> {
    print!(
        "Card '{}' does not exist. Create it? [y/N]: ",
        path.display()
    );
    io::stdout().flush()?;
    let mut answer = String::new();
    io::stdin().read_line(&mut answer)?;
    let trimmed = answer.trim().to_lowercase();
    Ok(trimmed == "y" || trimmed == "yes")
}

fn append_to_card(path: &Path, contents: &str) -> io::Result<()> {
    let mut file = OpenOptions::new().create(true).append(true).open(path)?;
    let trimmed = contents.trim_end_matches('\n');
    if trimmed.is_empty() {
        return Ok(());
    }

    let has_existing_content = file.metadata()?.len() > 0;
    if has_existing_content {
        writeln!(file)?;
    }
    writeln!(file, "{}", trimmed)?;
    Ok(())
}

fn capture_card_text(card_path: &str) -> io::Result<Option<String>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;
    terminal.show_cursor()?;

    let mut input = String::new();
    let mut confirmed = false;

    let editor_result: io::Result<()> = (|| {
        loop {
            terminal.draw(|frame| {
                let area = frame.area();
                let chunks = Layout::default()
                    .direction(Direction::Vertical)
                    .constraints([Constraint::Min(3), Constraint::Length(3)])
                    .split(area);

                let editor_block = Block::default()
                    .title(format!(" {} ", card_path).bold())
                    .borders(Borders::ALL);
                let editor = Paragraph::new(input.as_str())
                    .block(editor_block)
                    .wrap(Wrap { trim: false });
                frame.render_widget(editor, chunks[0]);

                let instructions =
                    Paragraph::new("Ctrl-S to save • Esc to cancel • Enter for newline")
                        .block(Block::default().borders(Borders::ALL).title(" Help "));
                frame.render_widget(instructions, chunks[1]);

                let cursor_line = input.split('\n').count().saturating_sub(1) as u16;
                let last_line = input.rsplit('\n').next().unwrap_or("");
                let cursor_col = last_line.chars().count() as u16;

                let cursor_x = chunks[0].x + 1 + cursor_col.min(chunks[0].width.saturating_sub(2));
                let cursor_y =
                    chunks[0].y + 1 + cursor_line.min(chunks[0].height.saturating_sub(2));
                frame.set_cursor_position((cursor_x, cursor_y));
            })?;

            if event::poll(Duration::from_millis(250))?
                && let Event::Key(key) = event::read()? {
                    if key.kind != KeyEventKind::Press {
                        continue;
                    }
                    match key.code {
                        KeyCode::Esc => break,
                        KeyCode::Char('s') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            confirmed = true;
                            break;
                        }
                        KeyCode::Char(c) if !key.modifiers.contains(KeyModifiers::CONTROL) => {
                            input.push(c);
                        }
                        KeyCode::Enter => input.push('\n'),
                        KeyCode::Tab => input.push('\t'),
                        KeyCode::Backspace => {
                            input.pop();
                        }
                        _ => {}
                    }
                }
        }
        Ok(())
    })();

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    editor_result?;
    Ok(if confirmed { Some(input) } else { None })
}
