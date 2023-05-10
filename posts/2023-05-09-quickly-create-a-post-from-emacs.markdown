---
title: Quickly create a post from Emacs
tags: emacs, hakyll
---

With the following snippet, I can call `M-x hakyll-blog-new-post`,
fill in the title and get started writing right away.

```lisp
(defgroup hakyll-blog nil
  "Hakyll Blog."
  :group 'applications)

(defcustom hakyll-blog-dir
  "~/blog"
  "Hakyll blog directory."
  :type 'string
  :group 'hakyll-blog)

(defcustom hakyll-blog-file-time-format
  "%Y-%m-%d"
  "Hakyll blog post filename time format."
  :type 'string
  :group 'hakyll-blog)

(defun hakyll-blog-new-post (title)
  "Create new blog post under `hakyll-blog-dir' with given TITLE."
  (interactive "sBlog post title: ")
  (find-file (hakyll-blog--file-format title))
  (insert (format "---\ntitle: %s\ntags: \n---\n\n" title)))

(defun hakyll-blog--file-format (title)
  "File name for TITLE post."
  (format "%s/posts/%s-%s.markdown"
          (expand-file-name hakyll-blog-dir)
          (format-time-string hakyll-blog-file-time-format)
          (s-dashed-words title)))
```
