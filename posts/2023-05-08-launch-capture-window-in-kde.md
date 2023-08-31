---
title: Launch Capture Window in KDE
tags: emacs
---

I created a custom shortcut `Meta-T` in KDE with the following
trigger:

```bash
emacsclient -e "(org-capture)" --create-frame
```

I went with calling `org-capture` directly as that shows a buffer
where I can choose which template to use. If I was using the
`org-protocol` feature, I'd need to setup one KDE shortcut per
template, the maintenance of which would annoy me to no end, on top of
filling up my global shortcuts.

But this did not raise the new frame in all cases. For example, if I
had my browser up and pressed `Meta-T`, the new Emacs frame would be
created but would not be focused.

To make that work, I needed the shortcut trigger to be:

```bash
emacsclient -e \
  "(progn (x-focus-frame nil) (org-capture))" \
  --create-frame
```

and I needed to add the following snippet to my Emacs config:

```lisp
(defun my/focus-new-client-frame ()
  (select-frame-set-input-focus (selected-frame)))

(add-hook 'server-after-make-frame-hook
  #'my/focus-new-client-frame)
```

I got that snippet from [this reddit
post](https://www.reddit.com/r/emacs/comments/it4m2w/comment/g5kr7z7/).

Now, when pressing `Meta-T` anywhere will create a new frame and focus
it.
