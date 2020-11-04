---
title: Configure Emacs to Write this Blog With Nix
tags: hakyll, haskell, nix, emacs, lsp, systemd
series: blog
---

We need to make Emacs find Haskell executables through Nix. It will
use [LSP](https://microsoft.github.io/language-server-protocol/) with
the [Ghcide](https://github.com/haskell/ghcide/) LSP server as basis
to parse the source code,
[Flycheck](https://www.flycheck.org/en/latest/) for live errors in the
buffer and [Brittany](https://hackage.haskell.org/package/brittany) to
format the code. Ghcide and Brittany are installed with
[Nix](https://nixos.org/).

To make all this work, we will use the following Emacs packages:

- [`nix-sandbox`](https://github.com/travisbhartwell/nix-emacs/#nix-sandbox) provides us with helper functions to get the current project's nix sandbox.
- [`nix-mode`](https://github.com/NixOS/nix-mode) makes it easy to edix `.nix` files as well as provides the `nix-build` function.
- [`lsp-mode`](https://emacs-lsp.github.io/lsp-mode) handles talking to a LSP server, here Ghcide.
- [`lsp-ui`](https://github.com/emacs-lsp/lsp-ui) shows LSP actions and various infos.
- [`company-lsp`](https://github.com/tigersoldier/company-lsp) provides autocompletion based on the LSP server.
- [`lsp-haskell`](https://github.com/emacs-lsp/lsp-haskell) is used by `lsp-mode` to talk to Ghcide.
- [`haskell-mode`](https://haskell.github.io/haskell-mode) provides syntax highlighting, hoogle integration and much more for editing Haskell files.
- [`flycheck`](https://www.flycheck.org/) provides syntax check highlighting.

By the way, I'm using
[use-package](https://github.com/jwiegley/use-package) with
[straight](https://github.com/raxod502/straight.el) to configure
Emacs.

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
`shell.nix` if it exists, or falls back to `default.nix` if it exists
or `nil` if none exist. It also defines `nix-shell-command` which,
from the docs:

> ``` commonlisp
> (defun nix-shell-command (sandbox &rest args)
>   "Assemble a command from ARGS that can be executed in the specified SANDBOX."
>   ...
> ```

Super useful for running `brittany` or `ghcide` inside our Nix
environment. We won't need to run those manually though.

Another useful function is `nix-compile` which interactively asks for
a sandbox and a command to run.

We add `nix-mode` mostly for its `nix-build` function. This allows us
to build the site executable from Emacs.

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
If we are, that is if `(nix-current-sandbox)` is not `nil`, then we
use `nix-sandbox`'s helpers to wrap around the `hoogle` and `brittany`
executables. If not, we directly call `hoogle` and `brittany`.

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

  (setq lsp-haskell-process-path-hie "ghcide"
		lsp-haskell-process-args-hie '()
		lsp-haskell-process-wrapper-function 'my/nix--lsp-haskell-wrapper))
```

Like for haskell-mode, the advanced configuration is focused on
wrapping the various commands with `nix-shell-command` and
`nix-shell-string`, with the wrapper being a pass-through if
`(nix-current-sandbox)` returns `nil`.

## Flycheck

Finally, we configure `flycheck` itself. Like for `lsp-haskell`, we
make it so `flycheck` can talk to Ghcide through Nix.

``` commonlisp
(use-package flycheck
  :straight t
  :after nix-sandbox

  :init
  (add-hook 'after-init-hook 'global-flycheck-mode)

  ;; from https://github.com/travisbhartwell/nix-emacs#flycheck
  (defun my/nix--flycheck-command-wrapper (command)
	(if-let ((sandbox (nix-current-sandbox)))
		(apply 'nix-shell-command (nix-current-sandbox) command)
	  command))
  (defun my/nix--flycheck-executable-find (cmd)
	(if-let ((sandbox (nix-current-sandbox)))
		(nix-executable-find (nix-current-sandbox) cmd)
	  (flycheck-default-executable-find cmd)))

  :config
  (setq flycheck-check-syntax-automatically '(save idle-change)
		flycheck-relevant-error-other-file-show nil
		flycheck-command-wrapper-function 'my/nix--flycheck-command-wrapper
		flycheck-executable-find 'my/nix--flycheck-executable-find)

  (add-to-list 'display-buffer-alist
			   `(,(rx bos "*Flycheck errors*" eos)
				 (display-buffer-reuse-window
				  display-buffer-in-side-window)
				 (side            . bottom)
				 (reusable-frames . visible)
				 (window-height   . 0.33))))
```

# Systemd-fu for Emacs Daemon

I will assume you use systemd to start emacs in daemon mode. If so,
create or update the `~/.config/systemd/user/emacs.service` file with
the same `NIX_*` and `PATH` `Environment` fields:

``` ini
[Unit]
Description=Emacs text editor
Documentation=info:emacs man:emacs(1) https://gnu.org/software/emacs/

[Service]
Type=forking
ExecStart=/usr/bin/emacs --daemon
ExecStop=/usr/bin/emacsclient --eval "(kill-emacs)"
Environment=NIX_PROFILES=/nix/var/nix/profiles/default %h/.nix-profile
Environment=NIX_PATH=%h/.nix-defexpr/channels
Environment=NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
Environment=PATH=%h/.nix-profile/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:
Restart=on-failure

[Install]
WantedBy=default.target
```

# Conclusion

That's it, you should be well equipped for editing your site.
Actually, everything we saw here is transferable to any Haskell code
running through Nix.
