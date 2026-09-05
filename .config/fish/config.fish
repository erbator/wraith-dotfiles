source /usr/share/cachyos-fish-config/cachyos-config.fish

function fish_greeting
	starship init fish | source
end

alias pacins="sudo pacman -S"
alias pacrem="sudo pacman -R"
alias cld="claude"
alias ff="fastfetch"
alias tan="z Documents/Notes/Learn"
alias tanang="z Documents/Notes/Learn/Angol"
alias tantor="z Documents/Notes/Learn/Tortenelem"
alias tannye="z Documents/Notes/Learn/Nyelvtan"
alias tanir="z Documents/Notes/Learn/Irodalom"

zoxide init fish | source

