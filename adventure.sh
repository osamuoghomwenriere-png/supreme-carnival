#!/usr/bin/env bash
# Adventure.sh - A small text adventure for Git Bash
# Save as adventure.sh, then:
# chmod +x adventure.sh
# ./adventure.sh

# -------------------------
# Config / Global Variables
# -------------------------
SAVEFILE="$HOME/.bash_adventure_save"
PLAYER_NAME=""
MAP_LEVEL=1
MAX_LEVEL=3

# Player stats
PLAYER_HP=100
PLAYER_MAX_HP=100
PLAYER_XP=0
PLAYER_LEVEL=1
PLAYER_ATK=10

# Position on map grid (row, col)
PLAYER_R=0
PLAYER_C=0

# Inventory (simple comma-separated string)
INVENTORY="potion:2"  # default: 2 potions (format: item:count,item2:count2)
GOLD=10

# Map sizes (rows x cols)
MAP_ROWS=5
MAP_COLS=5

# Random seed
RANDOM=$$$(date +%s)

# -------------------------
# Utility functions
# -------------------------
slow() {
  local text="$1"; local d=${2:-0.02}
  for ((i=0;i<${#text};i++)); do
    printf "%s" "${text:$i:1}"
    sleep "$d"
  done
  printf "\n"
}

pause() {
  read -rp "Press ENTER to continue..."
}

rand() { # rand min max
  local min=$1; local max=$2
  echo $(( RANDOM % (max - min + 1) + min ))
}

trim() { # trim whitespace
  echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Inventory helpers
get_item_count() {
  local item=$1
  echo "$INVENTORY" | awk -F, -v it="$item" '{
    for(i=1;i<=NF;i++){
      split($i,a,":"); if(a[1]==it){print a[2]; exit}
    }
    print 0
  }'
}
set_item_count() {
  local item=$1; local count=$2
  # remove existing and re-add if count>0
  local new=""
  IFS=',' read -ra parts <<< "$INVENTORY"
  for p in "${parts[@]}"; do
    k="${p%%:*}"; v="${p##*:}"
    if [[ $k != "$item" ]]; then
      [[ -n $new ]] && new+=","
      new+="$k:$v"
    fi
  done
  if (( count > 0 )); then
    [[ -n $new ]] && new+=","
    new+="$item:$count"
  fi
  INVENTORY="$new"
  INVENTORY=$(echo "$INVENTORY" | sed 's/^,*//; s/,*$//')
}

add_item() {
  local item=$1; local amt=${2:-1}
  local cur
  cur=$(get_item_count "$item")
  cur=$((cur+amt))
  set_item_count "$item" "$cur"
}

remove_item() {
  local item=$1; local amt=${2:-1}
  local cur
  cur=$(get_item_count "$item")
  cur=$((cur-amt))
  if (( cur < 0 )); then cur=0; fi
  set_item_count "$item" "$cur"
}

# -------------------------
# Map & Rooms
# -------------------------
# We'll represent maps as arrays of strings: each cell may contain:
# "." empty, "E" enemy, "C" chest, "S" shop, "X" exit to next level
declare -a MAP=() # will be rebuilt per level

generate_map() {
  MAP=()
  for ((r=0;r<MAP_ROWS;r++)); do
    row=""
    for ((c=0;c<MAP_COLS;c++)); do
      row+="."
    done
    MAP+=("$row")
  done

  # Place a few enemies, chests, and a shop and exit
  place_random "E" 5
  place_random "C" 2
  place_random "S" 1
  place_random "X" 1

  # ensure starting cell is empty
  set_cell 0 0 "."
  PLAYER_R=0; PLAYER_C=0
}

place_random() {
  local what=$1; local count=$2
  while (( count > 0 )); do
    local r=$((RANDOM % MAP_ROWS)); local c=$((RANDOM % MAP_COLS))
    if [[ "$(get_cell $r $c)" == "." ]]; then
      set_cell $r $c "$what"
      ((count--))
    fi
  done
}

get_cell() {
  local r=$1; local c=$2
  echo "${MAP[$r]:$c:1}"
}

set_cell() {
  local r=$1; local c=$2; local val=$3
  local row="${MAP[$r]}"
  MAP[$r]="${row:0:$c}$val${row:$((c+1))}"
}

print_map() {
  clear
  slow "Map (Level $MAP_LEVEL) - @ = you"
  for ((r=0;r<MAP_ROWS;r++)); do
    line=""
    for ((c=0;c<MAP_COLS;c++)); do
      if (( r == PLAYER_R && c == PLAYER_C )); then
        line+="@ "
      else
        ch="$(get_cell $r $c)"
        case $ch in
          ".") line+="· ";;  # dot
          "E") line+="? ";;  # unknown enemy
          "C") line+="□ ";;  # chest
          "S") line+="$ ";;  # shop
          "X") line+="> ";;  # exit
          *) line+="$ch ";; 
        esac
      fi
    done
    echo "$line"
  done
  echo
  echo "HP: $PLAYER_HP/$PLAYER_MAX_HP  Level: $PLAYER_LEVEL  XP: $PLAYER_XP  Gold: $GOLD"
  echo "Inventory: $INVENTORY"
}

# -------------------------
# Combat
# -------------------------
combat() {
  local enemy_name=$1
  local enemy_hp=$2
  local enemy_atk=$3
  slow "You encounter a $enemy_name! Prepare to fight."
  while (( enemy_hp > 0 && PLAYER_HP > 0 )); do
    echo
    echo "Enemy: $enemy_name  HP: $enemy_hp"
    echo "Your HP: $PLAYER_HP"
    echo "[A]ttack  [U]se item  [R]un"
    read -rp "> " action
    action=${action,,}
    if [[ $action == "a" || $action == "attack" ]]; then
      dmg=$(( PLAYER_ATK + RANDOM % (PLAYER_LEVEL*2 + 1) ))
      slow "You hit the $enemy_name for $dmg damage."
      (( enemy_hp -= dmg ))
    elif [[ $action == "u" || $action == "use" ]]; then
      use_item_in_combat || continue
    elif [[ $action == "r" || $action == "run" ]]; then
      roll=$((RANDOM % 100))
      if (( roll < 50 )); then
        slow "You escaped!"
        return 2
      else
        slow "You couldn't escape!"
      fi
    else
      slow "Invalid action."
      continue
    fi

    if (( enemy_hp > 0 )); then
      edmg=$(( enemy_atk + RANDOM % (MAP_LEVEL*3 + 1) ))
      slow "The $enemy_name hits you for $edmg."
      (( PLAYER_HP -= edmg ))
      if (( PLAYER_HP <= 0 )); then
        PLAYER_HP=0
        slow "You've been defeated..."
        return 1
      fi
    else
      slow "You defeated the $enemy_name!"
      gained=$((10 + RANDOM % 15 + MAP_LEVEL*5))
      GOLD=$((GOLD + RANDOM % 10 + MAP_LEVEL*3))
      PLAYER_XP=$((PLAYER_XP + gained))
      slow "You gained $gained XP and some gold!"
      level_up_check
      return 0
    fi
  done
}

use_item_in_combat() {
  local potions
  potions=$(get_item_count "potion")
  if (( potions > 0 )); then
    remove_item "potion" 1
    heal=$((15 + RANDOM % 10 + PLAYER_LEVEL*2))
    PLAYER_HP=$((PLAYER_HP + heal))
    if (( PLAYER_HP > PLAYER_MAX_HP )); then PLAYER_HP=$PLAYER_MAX_HP; fi
    slow "You used a potion and recovered $heal HP."
    return 0
  else
    slow "No potions left!"
    return 1
  fi
}

# -------------------------
# Level & XP
# -------------------------
level_up_check() {
  local need=$(( PLAYER_LEVEL * 50 ))
  if (( PLAYER_XP >= need )); then
    PLAYER_LEVEL=$((PLAYER_LEVEL + 1))
    PLAYER_MAX_HP=$((PLAYER_MAX_HP + 20))
    PLAYER_HP=$PLAYER_MAX_HP
    PLAYER_ATK=$((PLAYER_ATK + 3))
    PLAYER_XP=$((PLAYER_XP - need))
    slow "LEVEL UP! You are now level $PLAYER_LEVEL."
  fi
}

# -------------------------
# Rooms / Interactions
# -------------------------
handle_cell() {
  local cell
  cell=$(get_cell $PLAYER_R $PLAYER_C)
  case $cell in
    ".") slow "This place is quiet.";;
    "E")
      # create enemy depending on map level
      local ename="Goblin"
      local ehp=$((20 + MAP_LEVEL * 15 + RANDOM % 10))
      local eatk=$((5 + MAP_LEVEL * 3))
      combat "$ename" "$ehp" "$eatk"
      local res=$?
      if (( res == 0 )); then
        set_cell $PLAYER_R $PLAYER_C "."
      elif (( res == 1 )); then
        game_over
      fi
    ;;
    "C")
      slow "You found a chest!"
      open_chest
      set_cell $PLAYER_R $PLAYER_C "."
    ;;
    "S")
      enter_shop
    ;;
    "X")
      slow "You found the stair to the next level!"
      read -rp "Descend to the next level? (y/n) " yn
      if [[ ${yn,,} == "y" ]]; then
        next_level
      fi
    ;;
    *)
      slow "You see nothing noteworthy."
    ;;
  esac
}

open_chest() {
  local t=$((RANDOM % 3))
  case $t in
    0) add_item "potion" 1; slow "You found a potion!";;
    1) GOLD=$((GOLD + 20)); slow "You found 20 gold!";;
    2) add_item "bomb" 1; slow "You found a strange bomb (can be used in combat).";;
  esac
}

enter_shop() {
  slow "You enter a small traveling shop. The merchant nods."
  while true; do
    echo "Shop: [1] Potion (10g)  [2] Bomb (25g)  [3] Heal (full)  [4] Leave"
    read -rp "> " s
    case $s in
      1) if (( GOLD >= 10 )); then GOLD=$((GOLD-10)); add_item "potion" 1; slow "Bought potion."; else slow "Not enough gold."; fi;;
      2) if (( GOLD >= 25 )); then GOLD=$((GOLD-25)); add_item "bomb" 1; slow "Bought bomb."; else slow "Not enough gold."; fi;;
      3) if (( GOLD >= 30 )); then GOLD=$((GOLD-30)); PLAYER_HP=$PLAYER_MAX_HP; slow "Merchant healed you fully."; else slow "Not enough gold."; fi;;
      4) slow "You leave the shop."; break;;
      *) slow "Invalid option.";;
    esac
  done
}

# -------------------------
# Movement and Commands
# -------------------------
cmd_help() {
  cat <<EOF
Commands:
  n / north    - move up
  s / south    - move down
  e / east     - move right
  w / west     - move left
  map          - show map
  stats        - show player stats
  inv          - show inventory
  use <item>   - use an item (potion, bomb)
  save         - save game
  load         - load game
  quit         - quit game
  help         - show this help
EOF
}

use_item() {
  local item=$1
  if [[ -z $item ]]; then slow "Use what?"; return; fi
  case $item in
    potion)
      local cnt
      cnt=$(get_item_count "potion")
      if (( cnt > 0 )); then
        remove_item "potion" 1
        local heal=$((20 + RANDOM % 10 + PLAYER_LEVEL*2))
        PLAYER_HP=$((PLAYER_HP + heal)); if (( PLAYER_HP > PLAYER_MAX_HP )); then PLAYER_HP=$PLAYER_MAX_HP; fi
        slow "You drank a potion and recovered $heal HP."
      else
        slow "You have no potions."
      fi
    ;;
    bomb)
      local cnt
      cnt=$(get_item_count "bomb")
      if (( cnt > 0 )); then
        remove_item "bomb" 1
        slow "You hold a bomb (it will deal massive damage to the next enemy you fight)."
        add_item "armed_bomb" 1
      else
        slow "You have no bombs."
      fi
    ;;
    *)
      slow "You can't use that."
    ;;
  esac
}

use_armed_bomb_if_any() {
  local cnt
  cnt=$(get_item_count "armed_bomb")
  if (( cnt > 0 )); then
    remove_item "armed_bomb" 1
    echo "BOMB"
    return 0
  fi
  return 1
}

# -------------------------
# Save / Load / Game Over
# -------------------------
save_game() {
  cat > "$SAVEFILE" <<EOF
PLAYER_NAME=$PLAYER_NAME
PLAYER_HP=$PLAYER_HP
PLAYER_MAX_HP=$PLAYER_MAX_HP
PLAYER_XP=$PLAYER_XP
PLAYER_LEVEL=$PLAYER_LEVEL
PLAYER_ATK=$PLAYER_ATK
PLAYER_R=$PLAYER_R
PLAYER_C=$PLAYER_C
INVENTORY=$INVENTORY
GOLD=$GOLD
MAP_LEVEL=$MAP_LEVEL
MAP_ROWS=$MAP_ROWS
MAP_COLS=$MAP_COLS
MAP=BEGIN
$(printf "%s\n" "${MAP[@]}")
ENDMAP
EOF
  slow "Game saved to $SAVEFILE"
}

load_game() {
  if [[ ! -f "$SAVEFILE" ]]; then
    slow "No save file found."
    return 1
  fi
  # simple parser
  local inmap=0; MAP=()
  while IFS= read -r line; do
    if [[ "$line" == "MAP=BEGIN" ]]; then inmap=1; continue; fi
    if [[ "$line" == "ENDMAP" ]]; then inmap=0; continue; fi
    if (( inmap == 1 )); then MAP+=("$line"); continue; fi
    key="${line%%=*}"; val="${line#*=}"
    case $key in
      PLAYER_NAME) PLAYER_NAME=$val;;
      PLAYER_HP) PLAYER_HP=$val;;
      PLAYER_MAX_HP) PLAYER_MAX_HP=$val;;
      PLAYER_XP) PLAYER_XP=$val;;
      PLAYER_LEVEL) PLAYER_LEVEL=$val;;
      PLAYER_ATK) PLAYER_ATK=$val;;
      PLAYER_R) PLAYER_R=$val;;
      PLAYER_C) PLAYER_C=$val;;
      INVENTORY) INVENTORY=$val;;
      GOLD) GOLD=$val;;
      MAP_LEVEL) MAP_LEVEL=$val;;
      MAP_ROWS) MAP_ROWS=$val;;
      MAP_COLS) MAP_COLS=$val;;
    esac
  done < "$SAVEFILE"
  slow "Game loaded."
  return 0
}

game_over() {
  slow " >>> YOU DIED <<<"
  slow "Game over. Would you like to load your last save? (y/n)"
  read -rp "> " yn
  if [[ ${yn,,} == "y" ]]; then
    if load_game; then
      main_loop
    else
      slow "No save to load. Exiting."
      exit 0
    fi
  else
    slow "Goodbye."
    exit 0
  fi
}

# -------------------------
# Level progression
# -------------------------
next_level() {
  if (( MAP_LEVEL >= MAX_LEVEL )); then
    slow "You've reached the final level and found the treasure. You win!"
    exit 0
  fi
  MAP_LEVEL=$((MAP_LEVEL+1))
  MAP_ROWS=5
  MAP_COLS=5
  PLAYER_R=0; PLAYER_C=0
  # Improve enemy difficulty indirectly by using MAP_LEVEL in generation
  generate_map
  slow "You descend to level $MAP_LEVEL..."
}

# -------------------------
# Start / Intro / Main Loop
# -------------------------
intro() {
  clear
  slow "Welcome to Bash Adventure!"
  read -rp "Enter your name, traveler: " PLAYER_NAME
  PLAYER_NAME=$(trim "$PLAYER_NAME")
  if [[ -z $PLAYER_NAME ]]; then PLAYER_NAME="Adventurer"; fi
  slow "Greetings, $PLAYER_NAME. Your journey begins..."
  pause
}

main_loop() {
  while true; do
    print_map
    echo
    read -rp "> " cmd args
    cmd=${cmd,,}
    case $cmd in
      n|north) if (( PLAYER_R > 0 )); then PLAYER_R=$((PLAYER_R-1)); handle_cell; else slow "You can't go north."; fi;;
      s|south) if (( PLAYER_R < MAP_ROWS-1 )); then PLAYER_R=$((PLAYER_R+1)); handle_cell; else slow "You can't go south."; fi;;
      e|east)  if (( PLAYER_C < MAP_COLS-1 )); then PLAYER_C=$((PLAYER_C+1)); handle_cell; else slow "You can't go east."; fi;;
      w|west)  if (( PLAYER_C > 0 )); then PLAYER_C=$((PLAYER_C-1)); handle_cell; else slow "You can't go west."; fi;;
      map) print_map;;
      stats) echo "Name: $PLAYER_NAME"; echo "Level: $PLAYER_LEVEL"; echo "HP: $PLAYER_HP/$PLAYER_MAX_HP"; echo "ATK: $PLAYER_ATK"; echo "XP: $PLAYER_XP"; echo "Gold: $GOLD"; pause;;
      inv) echo "Inventory: $INVENTORY"; pause;;
      use)
        use_item "$args"
        ;;
      save) save_game;;
      load) load_game;;
      help) cmd_help; pause;;
      quit) slow "Save before quitting? (y/n)"; read -rp "> " yn; if [[ ${yn,,} == "y" ]]; then save_game; fi; slow "Farewell."; exit 0;;
      *) slow "Unknown command. Type 'help' for commands.";;
    esac

    # If player walks onto an enemy, handle_cell will call combat. 
    # If player HP is low, warn:
    if (( PLAYER_HP <= PLAYER_MAX_HP/4 )); then
      slow "Warning: your HP is low! Use a potion or visit a shop."
    fi
  done
}

# -------------------------
# Initialize game
# -------------------------
# If save exists, ask if load
if [[ -f "$SAVEFILE" ]]; then
  slow "A saved game was detected."
  read -rp "Load saved game? (y/n) " ans
  if [[ ${ans,,} == "y" ]]; then
    load_game
    main_loop
    exit 0
  fi
fi

# fresh game
intro
generate_map
main_loop