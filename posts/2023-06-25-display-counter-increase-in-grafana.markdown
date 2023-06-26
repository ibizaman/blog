---
title: Display Counter Increase in Grafana
tags: grafana
---

I had this problem where in grafana I wanted to show the increase of a gauge or counter over time. I
didn’t want to show the absolute value, but the increase.

There is no builtin function to handle showing increases where a time serie possibly has null values
and drops, like for example after a deploy where it starts from 0. So here are the steps to achieve
this.

Say you have this time series:

<img src="/images/grafana-20230625-1_time-series.png" />

and you want to produce this:

<img src="/images/grafana-20230625-2_result.png" />

We go from 7 to 8 at the start, then go from 0 to 5 at the end, that makes a total increase of 6.

First, you need to duplicate the time series with an offset of `$__interval`, here I plot both without (A) and with offset (B):

```
A:  sum (my_gauge)
B:  sum (my_gauge offset $__interval)
```

<img src="/images/grafana-20230625-3_offset.png" />

A naive A-B operation does not produce a good result: the total is wrong and we can see negative values

```
A:  sum (my_gauge)
B:  sum (my_gauge offset $__interval)
C:  $A - $B
```

<img src="/images/grafana-20230625-4_A-B.png" />

let’s first get rid of negative values:

```
C:  ($A - $B) >= 0
```

<img src="/images/grafana-20230625-5_A-Bbt0.png" />

The total is better, but it’s not 6 just yet.

You can see where the vertical bar is, we do not register the jump from 0 to 1, because there is no data point. To add data points, we need to do this:

```
A:  sum (my_gauge) or vector (0)
B:  sum (my_gauge offset $__interval) or vector (0)
```

If we again print the difference, we can see the total is accurate:

```
C:  ($A - $B) >= 0
```

<img src="/images/grafana-20230625-6_vector(0).png" />

But there’s a not pleasing gap there when the values drop. The final calculation is:

```
C:  ($A - $B) >= 0 or vector (0)
```

<img src="/images/grafana-20230625-7_final.png" />

The actual calculation I have is this ~~beautiful~~ horrendous formula:

```
(
    (sum (my_gauge)                    or vector (0))
  - (sum (my_gauge offset $__interval) or vector (0))
) >= 0 or vector (0)
```

which gives:

<img src="/images/grafana-20230625-2_result.png" />
