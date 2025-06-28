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
    "The things you think about determine the quality of your mind."
    "Nowhere can man find a quieter or more untroubled retreat than in his own soul."
    "Do not act as if you were going to live ten thousand years. Death hangs over you."
    "The object of life is not to be on the side of the majority, but to escape finding oneself in the ranks of the insane."
    "I have often wondered how it is that every man loves himself more than all the rest of men, but yet sets less value on his own opinion of himself than on the opinion of others."
    "Whenever you are about to find fault with someone, ask yourself the following question: What fault of mine most nearly resembles the one I am about to criticize?"
    "Do not indulge in dreams of having what you have not, but reckon up the chief of the blessings you do possess, and then thankfully remember how you would crave for them if they were not yours."
    "Here is a rule to remember in future, when anything tempts you to feel bitter: not 'This is misfortune,' but 'To bear this worthily is good fortune.'"
    "How ridiculous and how strange to be surprised at anything which happens in life."
    "Reject your sense of injury and the injury itself disappears."
    "Let not your mind run on what you lack as much as on what you have already."
    "Nothing happens to any man that he is not formed by nature to bear."
    "The only wealth which you will keep forever is the wealth you have given away."
    "Be content to seem what you really are."
    "Let men see, let them know, a real man, who lives as he was meant to live."
    "Forward, as occasion offers. Never look round to see whether any shall note it. Be satisfied with success in even the smallest matter, and think that even such a result is no trifle."
    "Because your own strength is unequal to the task, do not assume that it is beyond the powers of man; but if anything is within the powers and province of man, believe that it is within your own compass also."
    "Execute every act of thy life as though it were thy last."
    "Live as if you were to die tomorrow. Learn as if you were to live forever."
    "Begin each day by telling yourself: Today I shall be meeting with interference, ingratitude, insolence, disloyalty, ill-will, and selfishness."
    "Consider how much more you often suffer from your anger and grief, than from those very things for which you are angry and grieved."
    "When you wake up in the morning, tell yourself: The people I deal with today will be meddling, ungrateful, arrogant, dishonest, jealous and surly."
    "That which is not good for the swarm, neither is it good for the bee."
    "All things are linked with one another, and this oneness is sacred."
    "Whatever happens to you has been waiting to happen since the beginning of time."
    "Remember: Matter. How tiny your share of it. Time. How brief and fleeting your allotment of it. Fate. How small a role you play in it."
    "The art of living is more like wrestling than dancing."
    "Choose not to be harmed — and you won't feel harmed. Don't feel harmed — and you haven't been."
    "It's time you realized that you have something in you more powerful and miraculous than the things that affect you and make you dance like a puppet."
    "Dig within. Within is the wellspring of Good; and it is always ready to bubble up, if you just dig."
    "Understanding is the first step to acceptance, and only with acceptance can there be recovery."
    "You are a little soul carrying around a corpse."
    "Today I escaped anxiety. Or no, I discarded it, because it was within me, in my own perceptions — not outside."
    "We were born to work together."
    "Humans have come into being for the sake of each other, so either teach them, or learn to bear them."
    "Life is neither good or evil, but only a place for good and evil."
    "Death smiles at us all, but all a man can do is smile back."
    "Receive without conceit, release without struggle."
    "The best answer to anger is silence."
    "The more we value things outside our control, the less control we have."
    "How easy it is to repel and to wipe away every impression which is troublesome or unsuitable, and immediately to be in all tranquility."
    "Conceal a flaw, and the world will imagine the worst."
    "Be tolerant with others and strict with yourself."
    "Every living organism is fulfilled when it follows the right path for its own nature."
    "A man must stand erect, not be kept erect by others."
    "Natural ability without education has more often raised a man to glory and virtue than education without natural ability."
    "Time is a sort of river of passing events, and strong is its current; no sooner is a thing brought to sight than it is swept by and another takes its place."
    "Observe constantly that all things take place by change."
    "The memory of everything is very soon overwhelmed in time."
    "In your actions, don't procrastinate. In your conversations, don't confuse. In your thoughts, don't wander. In your soul, don't be passive or aggressive. In your life, don't be all about business."
    "If someone is able to show me that what I think or do is not right, I will happily change, for I seek the truth, by which no one was ever truly harmed."
    "Don't be ashamed to need help. Like a soldier storming a wall, you have a mission to accomplish. And if you've been wounded and you need a comrade to pull you up? So what?"
    "Whenever you want to cheer yourself up, consider the good qualities of your companions."
    "The nearer a man comes to a calm mind, the closer he is to strength."
    "Anything in any way beautiful derives its beauty from itself and asks nothing beyond itself."
    "Do what you will. Even if you tear yourself apart, most people will continue doing the same things."
    "Think of yourself as dead. You have lived your life. Now take what's left and live it properly."
    "You could leave life right now. Let that determine what you do and say and think."
    "Perfection of character is this: to live each day as if it were your last, without frenzy, without apathy, without pretense."
    "When you've done well and another has benefited by it, why like a fool do you look for a third thing on top — credit for the good deed or a favor in return?"
    "Words that everyone once used are now obsolete, and so are the men whose names were once on everyone's lips."
    "Everything is ephemeral — both memory and the object of memory."
    "Constantly regard the universe as one living being, having one substance and one soul."
    "Often injustice lies in what you aren't doing, not only in what you are doing."
    "All things fade and quickly turn to myth."
    "Soon you'll be ashes or bones. A mere name at most — and even that is just a sound, an echo."
    "In the life of a man, his time is but a moment, his being an incessant flux, his sense a dim rushlight, his body a prey of worms, his soul an unquiet eddy, his fortune dark, his fame doubtful."
    "That which is not good for the bee-hive cannot be good for the bees."
    "He who fears death either fears the loss of sensation or a different kind of sensation. But if thou shalt have no sensation, neither wilt thou feel any harm."
    "The act of dying is one of the acts of life."
)

# Colors for nice formatting
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
GRAY='\033[0;90m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# ASCII art of Marcus Aurelius
marcus_art=(
"     ___..._     "
"   .::::::::.    "
"  .:::::::::::.  "
" .:::::::::::::: "
" ::::::::::::::' "
" ::::::::::::'   "
" .:::::::::::.   "
" ::' \\  / '::   "
".:    ''    :.   "
"::   o  o   ::   "
"::     >     ::  "
"::    ---    ::  "
" ::  \\_/  ::'   "
"  ':::::::::'    "
"    ':::::'      "
"      ':'        "
)

# Alternative simpler ASCII art (bust style)
marcus_bust=(
"    .===========."
"   /    _____    \\"
"  |   /       \\   |"
"  |  |  ^   ^  |  |"
"  |  |    >    |  |"
"  |  |   ___   |  |"
"  |   \\  '-'  /   |"
"  |    '-----'    |"
"  |  M. AURELIUS  |"
"   \\  IMPERATOR  /"
"    '==========="
)

# Function to display a random quote
display_quote() {
    # Get random quote
    local random_index=$((RANDOM % ${#quotes[@]}))
    local quote="${quotes[$random_index]}"
    
    # Terminal width for centering
    local term_width=$(tput cols 2>/dev/null || echo 80)
    
    # Create a nice border
    local border_char="═"
    local corner_tl="╔"
    local corner_tr="╗"
    local corner_bl="╚"
    local corner_br="╝"
    local vertical="║"
    
    # Calculate border width
    local border_width=$((term_width - 2))
    local border=""
    for ((i=0; i<$border_width; i++)); do
        border+="$border_char"
    done
    
    # Display the quote with nice formatting
    echo
    echo -e "${PURPLE}${corner_tl}${border}${corner_tr}${NC}"
    
    # Display ASCII art centered
    echo -e "${PURPLE}${vertical}${NC}$(printf '%*s' $((term_width - 2)) ' ')${PURPLE}${vertical}${NC}"
    
    # Choose which ASCII art to use based on terminal width
    if [ $term_width -gt 60 ]; then
        # Use detailed ASCII art for wider terminals
        for line in "${marcus_art[@]}"; do
            local padding=$(( (term_width - ${#line} - 2) / 2 ))
            echo -e "${PURPLE}${vertical}${NC}$(printf '%*s' $padding ' ')${GRAY}${line}${NC}$(printf '%*s' $((term_width - padding - ${#line} - 2)) ' ')${PURPLE}${vertical}${NC}"
        done
    else
        # Use simpler ASCII art for narrower terminals
        for line in "${marcus_bust[@]}"; do
            local padding=$(( (term_width - ${#line} - 2) / 2 ))
            echo -e "${PURPLE}${vertical}${NC}$(printf '%*s' $padding ' ')${GRAY}${line}${NC}$(printf '%*s' $((term_width - padding - ${#line} - 2)) ' ')${PURPLE}${vertical}${NC}"
        done
    fi
    
    echo -e "${PURPLE}${vertical}${NC}$(printf '%*s' $((term_width - 2)) ' ')${PURPLE}${vertical}${NC}"
    echo -e "${PURPLE}${vertical}${NC}$(printf '%*s' $((term_width - 2)) ' ')${PURPLE}${vertical}${NC}"
    
    # Word wrap and display the quote
    echo -e "${CYAN}\"${quote}\"${NC}" | fold -s -w $((term_width - 6)) | while IFS= read -r line; do
        local padding=$(( (term_width - ${#line} - 2) / 2 ))
        echo -e "${PURPLE}${vertical}${NC}$(printf '%*s' $((padding - 1)) ' ')${CYAN}${line}${NC}$(printf '%*s' $((term_width - padding - ${#line} - 1)) ' ')${PURPLE}${vertical}${NC}"
    done
    
    echo -e "${PURPLE}${vertical}${NC}$(printf '%*s' $((term_width - 2)) ' ')${PURPLE}${vertical}${NC}"
    
    # Attribution
    local attribution="— Marcus Aurelius"
    local attr_padding=$(( (term_width - ${#attribution} - 2) / 2 ))
    echo -e "${PURPLE}${vertical}${NC}$(printf '%*s' $attr_padding ' ')${YELLOW}${attribution}${NC}$(printf '%*s' $((term_width - attr_padding - ${#attribution} - 2)) ' ')${PURPLE}${vertical}${NC}"
    
    echo -e "${PURPLE}${vertical}${NC}$(printf '%*s' $((term_width - 2)) ' ')${PURPLE}${vertical}${NC}"
    echo -e "${PURPLE}${corner_bl}${border}${corner_br}${NC}"
    echo
}

# Display the quote
display_quote