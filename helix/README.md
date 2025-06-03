# Paths of helix configurations

- ~/.config/helix
  - ~/.config/helix/runtime/grammars/*.so
  - ~/.config/helix/runtime/queries/*/*.scm
  - ~/.config/helix/runtime/themes/*.toml
  - ~/.config/helix/languages.toml
  - ~/.config/helix/config.toml

# Copy configurations

- from `https://github.com/helix-editor/helix`, copy `runtime/` and `languages.toml`
- from `./`, copy `config.toml`

# Build helix

```bash
cd $HOME/.config/
git clone https://github.com/helix-editor/helix
cd helix
cargo build --release --locked
cp target/release/hx $HOME/.cargo/bin
```
