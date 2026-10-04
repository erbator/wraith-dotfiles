source /usr/share/cachyos-fish-config/cachyos-config.fish


function fish_greeting
ff	
	# No starship inside st (TERM=st-256color); everywhere else keeps it
	if not string match -q 'st-*' -- $TERM
		starship init fish | source
	end
end

alias pacins="sudo pacman -S"
alias pacrem="sudo pacman -R"
alias cld="claude"
alias logout='loginctl terminate-session $XDG_SESSION_ID'

zoxide init fish | source


# jonaszfetch: fastfetch with image behind it (needs kitty)
alias ff="clear; kitten icat --z-index=-1 --place 66x14@0x0 --transfer-mode=file ~/.config/fastfetch/fetchimage.png; fastfetch --logo none --pipe false | sed 's/^/                              /'; printf '\n\n'"
