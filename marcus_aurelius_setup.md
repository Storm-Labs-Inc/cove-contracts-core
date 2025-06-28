# Marcus Aurelius Quotes for Terminal - Setup Guide

## Installation

1. **Move the script to a permanent location** (optional but recommended):
   ```bash
   mkdir -p ~/.config/terminal-quotes
   cp marcus_aurelius_quotes.sh ~/.config/terminal-quotes/
   ```

2. **Add to your .zshrc file**:
   
   If you don't have a .zshrc file yet, create it:
   ```bash
   touch ~/.zshrc
   ```
   
   Then add this line to your .zshrc:
   ```bash
   echo 'source ~/.config/terminal-quotes/marcus_aurelius_quotes.sh' >> ~/.zshrc
   ```
   
   Or if you kept the script in the current location:
   ```bash
   echo "source $(pwd)/marcus_aurelius_quotes.sh" >> ~/.zshrc
   ```

3. **Reload your shell configuration**:
   ```bash
   source ~/.zshrc
   ```

## Usage

Once installed, you'll see a random Marcus Aurelius quote every time you:
- Open a new terminal window
- Open a new terminal tab
- Start a new zsh session

## Customization

You can customize the script by editing `marcus_aurelius_quotes.sh`:
- Add more quotes to the `quotes` array
- Change the colors by modifying the color variables
- Adjust the border style by changing the `border_char` variable

## Troubleshooting

If quotes don't appear:
1. Make sure the script is executable: `chmod +x marcus_aurelius_quotes.sh`
2. Check that the path in your .zshrc is correct
3. Ensure you're using zsh as your shell: `echo $SHELL`

## Removing

To stop showing quotes, simply remove or comment out the source line from your .zshrc file.