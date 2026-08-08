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
`mode-transient-use-package` installs the `:transient`, `:major-transient`, and
`:minor-transient` keywords.

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

A prefix `:description` is rendered as an always-visible outer group heading,
so text properties such as Nerd Font families are preserved. A non-literal
description is automatically wrapped in a zero-argument function; strings,
function symbols, and explicit lambdas are left unchanged.

Suffix descriptions may be omitted while porting a command map:

```elisp
(mode-transient-define-prefix my-session ()
  ["Session"
   ("n" session-new)
   ("r" session-rename)])
```

Such suffixes show their command names through Transient's native
`:suffix-description` mechanism. Set that prefix option explicitly to override
the fallback, for example with `transient-command-summary-or-name` when command
docstring summaries are preferred.

## Major-mode menus

```elisp
(use-package eglot
  :ensure nil
  :major-transient
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
  :minor-transient
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

`M-x mode-transient-minor` is the unified minor-mode entry point. It opens the
only active registered minor-mode menu directly, or prompts when several are
active.

By default, mode-transient hides the cursor in its menu buffer so the title's
first character remains visible. Customize `mode-transient-hide-cursor` to nil
to retain Transient's cursor behavior. Other Transient menus are unaffected.

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
