# pandoc-lua-crossrefs

Pandoc Lua filter for cross-references. Faster than the non-Lua alternatives.

## Usage


### Markdown input

In order to reference an element, it must have an Id and be numbered. Sections, figures, tables, and equations are automatically numbered, unless they have the class `unnumbered`.

#### Specifying section and figure Ids

Section and figure Ids are specified as they would normally be in Pandoc's Markdown:
```markdown
# A section {#sec}

![Figure caption.](figure.jpg){#fig}
```

#### Specifying equation Ids

```markdown
$$
E=mc^2
$${#einstein .class key="val"}
```

#### Specifying table Ids

```markdown
Table: Table caption. {#id .class key=val}

FirstCol    SecondCol
----------  -----------
FirstCell   SecondCell
```

#### Cross-referencing syntax

The syntax used for cross-referencing items is briefly presented below using a series of examples.

| Pandoc's Markdown | Output |
| --- | --- |
| 1. `See #figid. See #eqid.` | See [Fig. 1](#). See [Eqn. 1](#). |
| 2. `See [#secid, #secid2, and #secid3].` | See Secs. [1](#), [2](#), and [3](#). |
| 3. `See [#figid and #figid2 or #figid3].` | See Figs. [1](#) and [2](#) or [3](#). |
| 4. `See [#figid; #figid2; #figid3].` | See Figs. [1](#), [2](#), and [3](#). |
| 5. `See [#tblid\; #tblid2\; #tblid3].` | See Tbls. [1](#); [2](#); [3](#). |
| 6. `See -#figid.` | See [1](#). |
| 7. `See [Figure -#figid].` | See [Figure 1](#). |

No particular Id naming convention is assumed - the user is free to use a naming convention like `#sec:id` for section Ids, or `#fig:id` for figure Ids, but can also choose not to do so. The cross-reference's prefix ("Sec.", "Fig.", "Eqn.", or "Tbl.") is inferred from the *type* of element that the Id references.

Note that for example 5 to work the `all_symbols_escapable` extension must be disabled (using `--from=markdown-all_symbols_escapable`). If this extension is not disabled, a double backslash (`\\\\`) must be used instead to escape the semicolon. This limitation cannot be resolved without upstream changes to pandoc.


## License

© 2025 R. N. West. Released under the [GPL](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html) version 2 or greater.
