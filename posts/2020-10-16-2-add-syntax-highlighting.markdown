---
title: Add Syntax Highlighting
tags: hakyll
---

This is "just" a matter of creating a CSS file and adding it to the
repository. The hard part is to have the patience to create the CSS
file, at least for me. I tried finding ready to use ones but I could
only find some on
[tejasbubane/hakyll-css](https://github.com/tejasbubane/hakyll-css). I
chose the
[zenburn](https://raw.githubusercontent.com/tejasbubane/hakyll-css/master/css/zenburn.css)
one.

Next steps are to copy paste its content to `css/syntax.css` then add
a link to the css file in `templates/default.html`:

``` html
<link rel="stylesheet" href="/css/syntax.css" />
```
