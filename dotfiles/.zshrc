
# Used to determine if configuration has
# been added to the zshrc already.
export REDACTED_CONFIG_SET=1

# Configure Node to store packages in a directory local to this user
# instead of in a global location.
NPM_PACKAGES=$HOME/.npm-packages
NODE_PATH="$NPM_PACKAGES/lib/node_modules:$NODE_PATH"
export N_PREFIX=$HOME/.n
export PATH="$N_PREFIX/bin:$NPM_PACKAGES/bin:$PATH"

export PHANTOMJS_CDNURL=https://REDACTED/artifactory/phantom-js-local

REGISTRY=https://REDACTED/artifactory/docker-all/
export DOCKER_OPTS="--insecure-registry $REGISTRY"

# Configure Python HTTPS requests
export REQUESTS_CA_BUNDLE=$HOME/curl-ca-bundle.crt

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Source local secrets (API keys, tokens, etc.)
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

# Initialize Starship prompt
eval "$(starship init zsh)"

# bun completions
[ -s "/Users/REDACTED/.bun/_bun" ] && source "/Users/REDACTED/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export PATH="$HOME/.local/bin:$PATH"
