#!/usr/bin/env bash

# Marcus Aurelius Quotes for Terminal
# Add this to your .zshrc: source /path/to/marcus_aurelius_quotes.sh

# Array of Marcus Aurelius quotes
quotes=(
    "You have power over your mind - not outside events. Realize this, and you will find strength."
    "The happiness of your life depends upon the quality of your thoughts."
    "Very little is needed to make a happy life; it is all within yourself, in your way of thinking."
    "When you arise in the morning, think of what a precious privilege it is to be alive - to breathe, to think, to enjoy, to love."
    "The best revenge is to be unlike him who performed the injury."
    "Accept the things to which fate binds you, and love the people with whom fate brings you together."
    "The soul becomes dyed with the color of its thoughts."
    "It is not death that a man should fear, but he should fear never beginning to live."
    "How much trouble he avoids who does not look to see what his neighbor says or does."
    "Waste no more time arguing about what a good man should be. Be one."
    "The impediment to action advances action. What stands in the way becomes the way."
    "Be like the rocky headland on which the waves constantly break. It stands firm, and round it the seething waters are laid to rest."
    "The universe is change; our life is what our thoughts make it."
    "Confine yourself to the present."
    "Loss is nothing else but change, and change is Nature's delight."
    "Everything we hear is an opinion, not a fact. Everything we see is a perspective, not the truth."
    "You always own the option of having no opinion."
    "How much more grievous are the consequences of anger than the causes of it."
    "If you are distressed by anything external, the pain is not due to the thing itself, but to your estimate of it."
    "When another blames you or hates you, or people voice similar criticisms, go to their souls, penetrate inside and see what sort of people they are."
    "The first rule is to keep an untroubled spirit. The second is to look things in the face and know them for what they are."
    "Never let the future disturb you. You will meet it, if you have to, with the same weapons of reason which today arm you against the present."
    "Our life is what our thoughts make it."
    "A man's worth is no greater than the worth of his ambitions."
    "Do every act of your life as though it were the very last act of your life."
    "What brings no benefit to the hive brings none to the bee."
    "At dawn, when you have trouble getting out of bed, tell yourself: 'I have to go to work — as a human being.'"
    "No man can escape his destiny, the next inquiry being how he may best live the time that he has to live."
    "Look well into thyself; there is a source of strength which will always spring up if thou wilt always look."
    "Adapt yourself to the life your lot has given you; and truly love the people with whom destiny has surrounded you."
)

# Colors for nice formatting
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Function to display a random quote
display_quote() {
    # Get random quote
    local random_index=$((RANDOM % ${#quotes[@]}))
    local quote="${quotes[$random_index]}"
    
    # Terminal width for centering
    local term_width=$(tput cols 2>/dev/null || echo 80)
    
    # Create a nice border
    local border_char="─"
    local border=""
    for ((i=0; i<$term_width; i++)); do
        border+="$border_char"
    done
    
    # Display the quote with nice formatting
    echo
    echo -e "${GRAY}${border}${NC}"
    echo
    
    # Word wrap and display the quote
    echo -e "${CYAN}\"${quote}\"${NC}" | fold -s -w $((term_width - 4)) | sed 's/^/  /'
    
    echo
    echo -e "${YELLOW}  — Marcus Aurelius${NC}"
    echo
    echo -e "${GRAY}${border}${NC}"
    echo
}

# Display the quote
display_quote