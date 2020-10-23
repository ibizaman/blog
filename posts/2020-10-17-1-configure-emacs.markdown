---
title: Configure Emacs to Write this Blog With Nix
tags: hakyll, haskell, nix, emacs, lsp
---

We need to make Emacs support Haskell through Nix. It will use
[LSP](https://microsoft.github.io/language-server-protocol/) through
[Ghcide](https://github.com/haskell/ghcide/) as basis to parse the
source code, [Flycheck](https://www.flycheck.org/en/latest/) for live
errors in the buffer and format the code through
[Brittany](https://hackage.haskell.org/package/brittany). Ghcide and
Brittany are installed with [Nix](https://nixos.org/).

To make Emacs work with Haskell being compiled through Nix, we will
use the following packages:

- [`nix-sandbox`](https://github.com/travisbhartwell/nix-emacs/#nix-sandbox) will provide us with helper functions to get the current project's nix sandbox.
- [`lsp-mode`](https://emacs-lsp.github.io/lsp-mode)
- [`lsp-ui`](https://github.com/emacs-lsp/lsp-ui)
- [`company-lsp`](https://github.com/tigersoldier/company-lsp)
- [`lsp-haskell`](https://github.com/emacs-lsp/lsp-haskell)
- [`haskell-mode`](https://haskell.github.io/haskell-mode)
- [`flycheck`](https://www.flycheck.org/)

Optionally, I recommend `nix-mode` to edit Nix files.

By the way, I'm using
[use-package](https://github.com/jwiegley/use-package) with
[straight](https://github.com/raxod502/straight.el).

Finally, to make this work with Emacs running as a daemon, there will
be some systemd-fu required.

# Emacs Setup

## Nix Sandbox and Helper

We add `nix-sandbox` and `nix-mode`:

``` commonlisp
(use-package nix-sandbox
  :straight t)

(use-package nix-mode
  :straight t
  :mode "\\.nix\\'"
  :init
  (require 'nix-build))
```

`nix-sandbox` defines `nix-current-sandbox` which returns the path to
`shell.nix` or if it does not exist to `default.nix` or `nil` if none
exist. It also defines `nix-shell-command` which, from the docs:

> ``` commonlisp
> (defun nix-shell-command (sandbox &rest args)
>   "Assemble a command from ARGS that can be executed in the specified SANDBOX."
>   ...
> ```

Super useful for running `brittany` or `ghcide` inside our Nix
environment.

Another useful function is `nix-compile` which interactively asks for
a sandbox and a command to run.

We add `nix-mode` for its `nix-build` function. This allows us to
build the site executable.

## lsp-mode, lsp-ui, company-lsp

These are fairly standard configuration whenever you use LSP in Emacs.
I reproduce them here for completeness.

``` commonlisp
(use-package lsp-mode
  :straight t
  :commands lsp
  :init
  (defun my/lsp-format-buffer-silent ()
    "Silence errors from `lsp-format-buffer'."
    (ignore-errors (lsp-format-buffer)))
  :hook ((sh-mode . lsp-deferred)
         (javascript-mode . lsp-deferred)
         (html-mode . lsp-deferred)
         (before-save . my/lsp-format-buffer-silent))
  :config
  (setq lsp-signature-auto-activate t)
  (lsp-lens-mode t))

(use-package lsp-ui
  :straight t
  :hook (lsp-mode-hook . lsp-ui-mode)
  :commands lsp-ui-mode
  :config
  (setq lsp-ui-flycheck-enable t
        lsp-ui-flycheck-live-reporting nil))

(use-package company-lsp
  :straight t
  :commands company-lsp
  :config
  (push 'company-lsp company-backends))
```

## Haskell-mode

Haskell-mode is used to edit haskell source code.

``` commonlisp
(use-package haskell-mode
  :straight t
  :after nix-sandbox

  :init

  (defun my/haskell-set-stylish ()
	(if-let* ((sandbox (nix-current-sandbox))
			  (fullcmd (nix-shell-command sandbox "brittany"))
			  (path (car fullcmd))
			  (args (cdr fullcmd)))
	  (setq-local haskell-mode-stylish-haskell-path path
				  haskell-mode-stylish-haskell-args args)))

  (defun my/haskell-set-hoogle ()
	(if-let* ((sandbox (nix-current-sandbox)))
		(setq-local haskell-hoogle-command (nix-shell-string sandbox "hoogle"))))

  :hook ((haskell-mode . capitalized-words-mode)
		 (haskell-mode . haskell-decl-scan-mode)
		 (haskell-mode . haskell-indent-mode)
		 (haskell-mode . haskell-indentation-mode)
		 (haskell-mode . my/haskell-set-stylish)
		 (haskell-mode . my/haskell-set-hoogle)
		 (haskell-mode . lsp-deferred)
		 (haskell-mode . haskell-auto-insert-module-template))

  :config

  (defun my/haskell-hoogle--server-command (port)
	(if-let* ((hooglecmd `("hoogle" "serve" "--local" "-p" ,(number-to-string port)))
			  (sandbox (nix-current-sandbox)))
		(apply 'nix-shell-command sandbox hooglecmd)
	  hooglecmd))

  (setq haskell-hoogle-server-command 'my/haskell-hoogle--server-command
		haskell-stylish-on-save t))
```

The advanced configuration is for handling `hoogle` and `brittany`
inside Nix. In both cases, we use buffer-local variables through the
`haskell-mode` hook and always check if we are in a Nix environment.
If we are, then we use `nix-sandbox`'s helpers to wrap around the
`hoogle` and `brittany` executables.

To search in the local database, we can then use
`haskell-hoogle-lookup-from-local`. On first call, it will start the
local server.

`brittany` will be called every time we save a buffer to format it.

## lsp-haskell

Now we setup the package that talks to Ghcide, our LSP server.

``` commonlisp
(use-package lsp-haskell
  :straight t
  :after nix-sandbox

  :init
  (setq lsp-prefer-flymake nil)
  (require 'lsp-haskell)

  :config

  ;; from https://github.com/travisbhartwell/nix-emacs#haskell-mode
  (defun my/nix--lsp-haskell-wrapper (args)
	(if-let ((sandbox (nix-current-sandbox)))
		(apply 'nix-shell-command sandbox args)
	  args))

  ;; from https://github.com/travisbhartwell/nix-emacs#flycheck
  (defun my/nix--flycheck-command-wrapper (command)
	(if-let ((sandbox (nix-current-sandbox)))
		(apply 'nix-shell-command (nix-current-sandbox) command)
	  command))
  (defun my/nix--flycheck-executable-find (cmd)
	(if-let ((sandbox (nix-current-sandbox)))
		(nix-executable-find (nix-current-sandbox) cmd)
	  (flycheck-default-executable-find cmd)))

  (setq lsp-haskell-process-path-hie "ghcide"
		lsp-haskell-process-args-hie '()
		lsp-haskell-process-wrapper-function 'my/nix--lsp-haskell-wrapper
		flycheck-command-wrapper-function 'my/nix--flycheck-command-wrapper
		flycheck-executable-find 'my/nix--flycheck-executable-find))
```

Like for haskell-mode, the advanced configuration is focused on
wrapping the various commands with `nix-shell-command` and
`nix-shell-string`, with the wrapper being a pass-through if
`(nix-current-sandbox)` returns `nil`.

We make it so Flycheck talks to Ghcide inside the Nix environment.

# Flycheck

Finally, we configure flycheck itself. There is nothing tied to Nix or
any other package we talked about but I still reproduced my config
here for completeness.

``` commonlisp
(use-package flycheck
  :straight t
  :init
  (add-hook 'after-init-hook 'global-flycheck-mode)
  :config
  (setq flycheck-check-syntax-automatically '(save idle-change)
		flycheck-relevant-error-other-file-show nil)
  (add-to-list 'display-buffer-alist
			   `(,(rx bos "*Flycheck errors*" eos)
				 (display-buffer-reuse-window
				  display-buffer-in-side-window)
				 (side            . bottom)
				 (reusable-frames . visible)
				 (window-height   . 0.33))))
```

# Conclusion

That's it, you should be well equipped for editing your site.
