---
title: Cache Go tests in CI
tags: go
wip: true
---

If your tests take more than, say, 30 seconds to run, you will like the speed improvement that comes
with caching test results.

This concern came up at work where our whole test suite was taking up to 10 minutes to run.

# Caching locally

A few things:
- 
