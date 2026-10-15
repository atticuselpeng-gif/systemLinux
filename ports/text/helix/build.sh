# helix needs its runtime folder (themes, queries, tree-sitter grammars) next to the program. Its build fetches and
# compiles the grammars with git; the runtime goes to $PREFIX/lib/helix/runtime, compiled into hx as the default.
export HELIX_DEFAULT_RUNTIME=$PREFIX/lib/helix/runtime
cargo install --locked --no-track --path helix-term --root "$DESTDIR$PREFIX"
rm -rf runtime/grammars/sources
mkdir -p "$DESTDIR$PREFIX/lib/helix"
cp -r runtime "$DESTDIR$PREFIX/lib/helix/"
