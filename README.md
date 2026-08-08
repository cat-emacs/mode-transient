# mode-transient

`mode-transient` builds composable [Transient](https://github.com/magit/transient)
menus for named commands, major modes, and minor modes. Contributions use
Transient's native group and suffix syntax instead of an adapter DSL.

## Installation

```elisp
(use-package mode-transient
  :vc (:url "https://github.com/cat-emacs/mode-transient")
  :demand t
  :config
  (require 'mode-transient-use-package))
```

The core library does not depend on `use-package`. Requiring
`mode-transient-use-package` installs the `:transient`, `:mode-transient`, and
`:minor-mode-transient` keywords.

## Named menus

Define a prefix once and extend it from multiple package declarations:

```elisp
(mode-transient-define-prefix my-tools ()
  :description (format "Tools for %s" (buffer-name)))

(use-package compile
  :ensure nil
  :transient
  (my-tools
   ["Build"
    ("c" "Compile" compile)]))
```

A non-literal prefix `:description` is automatically wrapped in a
zero-argument function. Strings, function symbols, and explicit lambdas are
left unchanged.

## Major-mode menus

```elisp
(use-package eglot
  :ensure nil
  :mode-transient
  (prog-mode
   ["LSP"
    ("e" "Start Eglot" eglot)
    ("r" "Rename" eglot-rename)]))
```

Run `M-x mode-transient` to open the closest menu registered for the current
major mode or one of its parents.

## Minor-mode menus and keys

```elisp
(use-package example-mode
  :minor-mode-transient
  (example-mode
   (:key "C-c e")
   ["Example"
    ("r" "Refresh" example-refresh)]))
```

The keymap defaults to `example-mode-map`. Use `:keymap` to override it and
`:feature` when the map is provided by a feature other than the package named
by `use-package`.

To keep keys in a central configuration, omit `:key` and bind the generated
command elsewhere:

```elisp
(keymap-set mode-specific-map "e"
            #'mode-transient/minor/example-mode)
```

`M-x mode-transient-minor` selects among active minor modes with registered
menus.

## Native Transient features

Group vectors and suffixes retain native Transient behavior, including levels,
predicates, dynamic descriptions, infix arguments, and nested prefixes.
Contributions with identical named group headers are merged in registration
order.

## Development

The CI workflow reuses `cat-emacs/.github` and tests Emacs 29.4 and 30.2.

```sh
make install-deps
make
```

Licensed under GPL-3.0-or-later.
