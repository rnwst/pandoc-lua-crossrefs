# Equation cross-reference {#sec1}

$$E=mc$${#eq1}

See #eq1.


# Figure cross-reference {#sec2}

See #fig1.

![test](fig1.jpg){#fig1}


# Table cross-reference {#sec3}

See #tbl1.

Symbol    Meaning
--------  --------
b         wingspan

Table: Table caption {#tbl1 .class key=val}


# Groups of cross-references

![test](fig2.jpg){#fig2}

![test](fig3.jpg){#fig3}

See [#sec1, #sec2, and #sec3].

See [#fig1 and #fig2 or #fig3].

See [#fig1; #fig2; #fig3].

See [#fig1\; #fig2\; #fig3].


# Groups of cross-references of non-uniform types

See [#sec1; #fig2; #fig3].

See [#sec1; #sec2; #fig3].

See [#eq1; #fig2; #sec3].

**Currently fails:**
See [#eq1; #fig1; #fig2; #fig3].


# Cross-reference with suppressed prefix

See -#fig1.


# Pathological cases

**Currently fails:**
Cross-reference group that doesn't begin and end in a cross-reference: See [in particular #sec1, #sec2, and #sec3 as well.]
