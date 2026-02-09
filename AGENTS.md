# Gaelan's Emacs configuration Nix package

## Common Tasks
Build the package: `nix-build`
Run emacs from package: `./result/bin/emacs`
Check generated emacs lisp: `nix-build && ./result/bin/emacs --batch --load org -f org-babel-tangle init.org`
