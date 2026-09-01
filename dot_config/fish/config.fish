# Interactive fish for Ghostty/kitty. Login shell stays bash.

if status is-interactive
    set -g fish_greeting

    fish_add_path -g $HOME/.local/bin $HOME/.cargo/bin

    if command -q starship
        starship init fish | source
    end

    if command -q zoxide
        zoxide init fish --cmd j | source
    end

    if functions -q fzf_key_bindings
        fzf_key_bindings
    end

    if command -q fastfetch; and isatty stdout
        fastfetch
    end
end
