---
title: Improving Git Speed with Large Repositories
tags: git, performance
---

It's no secret that the [nixpkgs][repo] repo is quite big.
Big enough to slow down git operations to noticeable lags.

[repo]: https://github.com/NixOS/nixpkgs/

I use Emacs and Magit and with those, loading the status page takes - I kid you not - 15 seconds.
Now, I don't mind waiting a couple seconds, but here it's just over my patience threshold.

I must say, the conclusion will be obvious in retrospective but since we use layers upon layers of software - here Magit over Emacs over Git - it's not always obvious where the fix should happen.
And that's what prompted me to write this blog post, so I can showcase how to debug such a situation.

So, to investigate what's going on, I toggled verbose logging with `M-x magit-toggle-verbose-refresh` so that loading the `magit-status` prints loading time.
This is what I get:

```bash
Refreshing magit...
Running magit-pre-refresh-hook...done (0.012s)
Refreshing buffer ‘magit: nixpkgs’...
  magit-insert-error-header                0.000006 
  magit-insert-diff-filter-header          0.009790 
  magit-insert-head-branch-header          0.012734 !
  magit-insert-upstream-branch-header      0.000090 
  magit-insert-push-branch-header          0.012852 !
  magit-insert-tags-header                 8.128425 !!
  magit-insert-status-headers              8.173127 !!
  magit-insert-merge-log                   0.004723 
  magit-insert-rebase-sequence             0.000119 
  magit-insert-am-sequence                 0.000066 
  magit-insert-sequencer-sequence          0.000206 
  magit-insert-bisect-output               0.000063 
  magit-insert-bisect-rest                 0.000054 
  magit-insert-bisect-log                  0.000055 
  magit-insert-untracked-files             0.394513 !!
  magit-insert-unstaged-changes            0.055459 !!
  magit-insert-staged-changes              0.036347 !!
  magit-insert-stashes                     0.021789 !
  m..-in..-unpushed-to-pushremote          0.038461 !!
  m..-in..-unpushed-to-upstream-or-recent  0.344540 !!
  m..-in..-unpulled-from-pushremote        0.039289 !!
  magit-insert-unpulled-from-upstream      0.000005 
  magit-insert-local-branches              6.681158 !!
  forge-insert-issues                      0.013407 !
  forge-insert-pullreqs                    0.002832 
Refreshing buffer ‘magit: nixpkgs’...done (15.884s)
Running magit-post-refresh-hook...done (0.009s)
Refreshing magit...done (15.907s, cached 64/93 (69%))
```

Several steps take a long time. The first being `magit-insert-tags-header`.

Thanks to the [helpful][helpful] package, I can `C-h h magit-insert-tags-header` and see the source code of the function directly in the help buffer.
And here it is:

[helpful]: https://github.com/Wilfred/helpful

```lisp
(defun magit-insert-tags-header ()
  "Insert a header line about the current and/or next tag."
  (let* ((this-tag (magit-get-current-tag nil t))
         (next-tag (magit-get-next-tag nil t))
         (this-cnt (cadr this-tag))
         (next-cnt (cadr next-tag))
         (this-tag (car this-tag))
         (next-tag (car next-tag))
         (both-tags (and this-tag next-tag t)))
    (when (or this-tag next-tag)
      (magit-insert-section (tag (or this-tag next-tag))
        (insert (format "%-10s" (if both-tags "Tags: " "Tag: ")))
        (cl-flet ((insert-count (tag count face)
                    (insert (concat (propertize tag 'font-lock-face 'magit-tag)
                                    (and (> count 0)
                                         (format " (%s)"
                                                 (propertize
                                                  (format "%s" count)
                                                  'font-lock-face face)))))))
          (when this-tag  (insert-count this-tag this-cnt 'magit-branch-local))
          (when both-tags (insert ", "))
          (when next-tag  (insert-count next-tag next-cnt 'magit-tag)))
        (insert ?\n)))))
```

From looking at all the functions in there, the two that call to git and are likely the slow ones are in the first two lines: `(magit-get-current-tag nil t)` and `(magit-get-next-tag nil t)`.

So I copy pasted the two expressions one by one then ran them with `Alt-:` followed by `C-y` and `Enter`.
The `magit-get-current-tag` is the one actually taking those 8 seconds.
The second one takes no time to run.

Going one level deeper, `C-h h` reveals the source code for `magit-get-current-tag`:

```lisp
(defun magit-get-current-tag (&optional rev with-distance)
  "Return the closest tag reachable from REV.

If optional REV is nil, then default to `HEAD'.
If optional WITH-DISTANCE is non-nil then return (TAG COMMITS),
if it is `dirty' return (TAG COMMIT DIRTY). COMMITS is the number
of commits in `HEAD' but not in TAG and DIRTY is t if there are
uncommitted changes, nil otherwise."
  (and-let* ((str (magit-git-str "describe" "--long" "--tags"
                                 (and (eq with-distance 'dirty) "--dirty")
                                 rev)))
    (save-match-data
      (string-match
       "\\(.+\\)-\\(?:0[0-9]*\\|\\([0-9]+\\)\\)-g[0-9a-z]+\\(-dirty\\)?$" str)
      (if with-distance
          `(,(match-string 1 str)
            ,(string-to-number (or (match-string 2 str) "0"))
            ,@(and (match-string 3 str) (list t)))
        (match-string 1 str)))))
```

Here too the probable slow call is easy to spot, it's in the first line, the call to `magit-git-str`.
I ran the expression and indeed, it's the slow one.

This means the slowness is with git!
I thus ran the command in the terminal directly: `git describe --long --tags` and indeed, that took roughly 8 seconds to run.
I tried without arguments but no improvements.

Next step, how to make git faster?
I found [this StackOverflow answer][so1] and tried it.

```bash
git gc --aggressive
```

But the terminal got killed after running for around 5 minutes because my machine was out of memory!

[so1]: https://stackoverflow.com/a/3339609/1013628

So, how to make git take less memory?
I found [this other StackOverflow question][so2] with the answer highlighted at the top.
I thus added the following snippet to the local `.git/config` file:

[so2]: https://stackoverflow.com/questions/8214321/git-gc-using-excessive-memory-unable-to-complete

```ini
[pack]
    packSizeLimit = 64m
    threads = 6
[gc]
    aggressiveWindow = 150
```

I bumped `pack.threads` from 1 as recommended in the post to 6 just to speed things up a bit.
I have no idea what the best number would be, I just tried a few.
The process now took at most half of CPU time and 70% of 16Gb of memory.
At least it was in check and could complete.

Same for the other fields.
I must admit I didn't look up what they meant nor did check if they were good values.
I just wanted to fix this quickly.

So with that, I could run `git gc --aggressive` again which, after about 45 minutes, gave me:

```bash
Enumerating objects: 5289057, done.
Counting objects: 100% (5289057/5289057), done.
Delta compression using up to 6 threads
Compressing objects: 100% (4911761/4911761), done.
Writing objects: 100% (5289057/5289057), done.
Total 5289057 (delta 3262154), reused 1315941 (delta 0), pack-reused 0 (from 0)
Checking connectivity: 5289057, done.
Expanding reachable commits in commit graph: 717447, done.
Writing out commit graph in 5 passes: 100% (3587235/3587235), done.
```

Yes, that took 45 minutes.

But at least, the `git describe` operation was an order of magnitude faster now:

```bash
$ time git describe --long --tags
24.05-pre-59983-g7041e60248e5

real    0m0.621s
user    0m0.521s
sys     0m0.099s
```

And indeed, refreshing the Magit status buffer takes around 3 seconds only now:

```bash
Refreshing buffer ‘magit: nixpkgs’...
  magit-insert-error-header                0.000812 
  magit-insert-diff-filter-header          0.000052 
  magit-insert-head-branch-header          0.022620 !
  magit-insert-upstream-branch-header      0.000064 
  magit-insert-push-branch-header          0.017885 !
  magit-insert-tags-header                 0.660671 !!
  magit-insert-status-headers              0.707210 !!
  magit-insert-merge-log                   0.000586 
  magit-insert-rebase-sequence             0.000657 
  magit-insert-am-sequence                 0.000045 
  magit-insert-sequencer-sequence          0.000126 
  magit-insert-bisect-output               0.000477 
  magit-insert-bisect-rest                 0.000030 
  magit-insert-bisect-log                  0.000024 
  magit-insert-untracked-files             0.329094 !!
  magit-insert-unstaged-changes            0.046189 !!
  magit-insert-staged-changes              0.036653 !!
  magit-insert-stashes                     0.035565 !!
  m..-in..-unpushed-to-pushremote          0.023885 !
  m..-in..-unpushed-to-upstream-or-recent  0.077200 !!
  m..-in..-unpulled-from-pushremote        0.022968 !
  magit-insert-unpulled-from-upstream      0.000074 
  magit-insert-local-branches              1.507013 !!
  forge-insert-issues                      0.024168 !
  forge-insert-pullreqs                    0.014356 !
Refreshing buffer ‘magit: nixpkgs’...done (3.228s)
```

There could be more optimizations to be done, but that's enough for me for now.

Conclusion: let's not forget to run `git gc` from time to time, especially for big repositories.
