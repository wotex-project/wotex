# Draft brand artwork handoff

Status: unapproved draft, 2026-10-21. Package path: `packages/wotex-lab`.
Source baseline: repository commit `6e10c129bc1b3d2f905d3dd55abd64a8f7964d84`.
The [design contract](../plans/brand-and-lab-design.md) owns acceptance.
This handoff records exported artwork; it does not select the final identity,
change the Lab UI or establish completion of WLB-C15.

## Native sources and treatments

The editable source is
[WoTEx — Brand Identity](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0).
It retains the original 192 px typographic study and adds three component
families: Signature treatments (nine variants), Letter W tile (three) and
Repository preview (two). Masters remain outside the review frames; the
reviews use linked instances, native text and auto-layout.

The [artwork review](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0?node-id=5-50)
shows Name, Descriptor and Lab lockups in Ink, Inverse and Black. The
[usage review](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0?node-id=6-26)
shows protected space, proposed digital minimum widths and icon specimens.
The [channel review](https://www.figma.com/design/R5PCVQOfoJV6rrsJ6ZTSv0?node-id=7-19)
shows the repository preview treatments. Both carry the source README's
experimental status.

Eleven fixed artwork variables alias the existing palette or define artwork
geometry. The brand file now has fifty-two variables and eight text styles.
These new roles are design-only and have no implemented CSS projection.
Lab UI semantic modes, code tokens and the Workbench file are unchanged.

| Treatment | Foreground | Background | Calculated sRGB contrast |
| --- | --- | --- | --- |
| Ink on Paper | `#263044` | `#F4F2EE` | 11.823:1 |
| Ice on Navy | `#E0F4FF` | `#142B50` | 12.443:1 |
| Black on White | `#000000` | `#FFFFFF` | 21:1 |

The native wordmark master uses Inter Semi Bold at 96 px, derived from the
existing Inter direction. The descriptor uses Inter Medium; the Lab label
uses Inter Semi Bold at 32 px. Proposed clear space is one quarter of the
wordmark font size: 24 px at the master size, scaled with the artwork and
reserved outside its complete frame. Proposed minimum widths are 80 px for
Name, 320 px for Descriptor and 160 px for Lab. These are review specimens,
not approved usage rules. The Letter W tile is a small-icon study requiring
recognition review and a visible WoTEx label in its surrounding product.

## Export and validation evidence

Twelve SVGs were exported through Figma's native SVG export with outlined
text and sRGB colours. Their viewBoxes match the source dimensions. XML
inspection found paths and no text, image, script, foreign-object, use or
external-reference nodes. The native masters retain editable text.

Eleven PNGs were exported through Figma's native PNG export with sRGB:
three icon treatments at 16, 32 and 512 px, and two repository previews at
1280 × 640. Python standard-library checks verified every PNG chunk CRC,
decoded the filtered RGBA pixels, and checked dimensions, alpha ranges and
file sizes. Icon corners retain transparency; both repository previews are
fully opaque. The Paper and Navy preview files contain 35,216 and 35,575 bytes.

[GitHub's repository-preview guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview)
recommends 1280 × 640 and a PNG, JPG or GIF below 1 MB. The two native PNG
exports meet those dimensions and size bounds. No repository setting was
changed or destination upload tested.

Full-view native renders were inspected for all three new review boards,
including all nine lockups and actual-size minimum/icon specimens. A coloured
icon in the monochrome column was replaced with a black/white variant, then
the corrected board was reviewed. The native boards contained no image fills,
used Inter and had no text outside their containing frame bounds. The exported
Navy preview, 32 px Navy icon and 16 px monochrome icon were also inspected as
local PNGs. Standalone SVG rendering outside Figma, destination integration,
font-build capture, a native archive and an independent restore were not run.

## Asset identities

Repository asset links pin artwork commit `42f3fc5a48a5ad56760abb3c689c5c488375dd35`; the files
live outside the package documentation tree.

The files below are exact draft exports. Changing a native source requires a
fresh export and renewed comparison; these hashes do not qualify later edits.
Artwork and font attribution appear in the
[asset notice](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/NOTICE). The upstream font licence
is a reference; it does not identify Figma's unexposed font build. No font
software, imported photograph or third-party brand artwork was bundled.

| Asset | Native node | Dimensions | SHA-256 |
| --- | --- | --- | --- |
| [wotex-descriptor-ink-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-descriptor-ink-draft.svg) | `5:23` | 322 × 134 | `4c31a8ffb08234238b0fc2eba2edb68c31962ce476441443a78d8ac67bc42238` |
| [wotex-descriptor-inverse-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-descriptor-inverse-draft.svg) | `5:24` | 322 × 134 | `d71991e289ef248d2af9fdaf8f041b505d16b0cbce9b3d7cbfdd57ac5d6d8be6` |
| [wotex-descriptor-mono-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-descriptor-mono-draft.svg) | `5:25` | 322 × 134 | `8dedc0505c5e4691d056b9f56fb464d11a8e83576a25e991d93f52c31fca250e` |
| [wotex-lab-ink-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-lab-ink-draft.svg) | `5:26` | 322 × 152 | `afe1144d561363f5ea4414e5d3367fd001ddee5734e76d7a4ad39b87050cd41a` |
| [wotex-lab-inverse-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-lab-inverse-draft.svg) | `5:27` | 322 × 152 | `7f65d4e093a6737f3ee17eab61b2121b5e70cca1b905926d5556ff487d43bf53` |
| [wotex-lab-mono-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-lab-mono-draft.svg) | `5:28` | 322 × 152 | `6cc25194918640d251ebee677d531e2097a767ae17d88d35e0339d3ba264183c` |
| [wotex-name-ink-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-name-ink-draft.svg) | `5:20` | 322 × 106 | `003997bde4a4a1860d71f9bc5d4bbfd9e9fa31659684bf6b29cac5217b76e97c` |
| [wotex-name-inverse-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-name-inverse-draft.svg) | `5:21` | 322 × 106 | `99c84ba1ff3b772a5b393f760f395b9da8a4bd0a348e41d02a9e5c57bea7a1f2` |
| [wotex-name-mono-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-name-mono-draft.svg) | `5:22` | 322 × 106 | `35ef3e20dad1d9d4681e295fac610dd173ad1d5bc07aaeef63087bfc548c03d0` |
| [wotex-repository-preview-navy-draft.png](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-repository-preview-navy-draft.png) | `7:3` | 1280 × 640 | `46f3c3b41e5c3853701ddcff68ceeee85c5cbe5c6c66053dcfa2783ccd25a2b9` |
| [wotex-repository-preview-paper-draft.png](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-repository-preview-paper-draft.png) | `7:2` | 1280 × 640 | `97749f768d63299b10c81d4b5f4993e5c5a9c4030c052fc19b9aa3de45c51284` |
| [wotex-w-tile-mono-16-draft.png](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-mono-16-draft.png) | `6:24` | 16 × 16 | `a0d78ec10d8f7bcc9633455019b7bc4a7c345a5e34b883b33d6fe4ead8f20fda` |
| [wotex-w-tile-mono-32-draft.png](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-mono-32-draft.png) | `6:24` | 32 × 32 | `1265199cd8a073216bc76a360b25d70166a36cd51a999972157e56ad2919856c` |
| [wotex-w-tile-mono-512-draft.png](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-mono-512-draft.png) | `6:24` | 512 × 512 | `1e448a5989a984d0a74c5e1098a26e4d012b381955395c40528f898ea2f44c19` |
| [wotex-w-tile-mono-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-mono-draft.svg) | `6:24` | 128 × 128 | `dec32b28c300c8c174dbd8d74b7909ea72cb167e6b9ded90ef8d5779ed5f7dc4` |
| [wotex-w-tile-navy-16-draft.png](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-navy-16-draft.png) | `5:45` | 16 × 16 | `1607917ee33ab511ceb7f55d93783afa059fd498e1a04d0115803499430a07a1` |
| [wotex-w-tile-navy-32-draft.png](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-navy-32-draft.png) | `5:45` | 32 × 32 | `48f825898ec6399afbda22c8fd904c722332c647ae8a54c42e2eb2ebe3e5b634` |
| [wotex-w-tile-navy-512-draft.png](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-navy-512-draft.png) | `5:45` | 512 × 512 | `9620b44c2bc778e58463603214d21b13a9daa1bd90daf64a80ebadf649c19561` |
| [wotex-w-tile-navy-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-navy-draft.svg) | `5:45` | 128 × 128 | `0042e8a99a1fb95afd9b68a9b9caa428683701d535f549247c3f4392a6704832` |
| [wotex-w-tile-paper-16-draft.png](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-paper-16-draft.png) | `5:46` | 16 × 16 | `894c5e6a9a42d85d3eebf6b0ceb9438eb131f21107557881ed765dbed4a2e480` |
| [wotex-w-tile-paper-32-draft.png](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-paper-32-draft.png) | `5:46` | 32 × 32 | `25d710696ad659a6961e4a99561d07d0de781fe17e4ab032c20047e77bc9c87d` |
| [wotex-w-tile-paper-512-draft.png](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-paper-512-draft.png) | `5:46` | 512 × 512 | `d2b3ed6d43027b7d33973cf21262084258aa2311a9735d40fff12c45a3d3a851` |
| [wotex-w-tile-paper-draft.svg](https://github.com/wotex-project/wotex/blob/42f3fc5a48a5ad56760abb3c689c5c488375dd35/docs/assets/brand/draft/wotex-w-tile-paper-draft.svg) | `5:46` | 128 × 128 | `66190bde0647440cf374f710ba95f5826b62ebf995b2d97d6815be77cba03f61` |

Final mark selection, approved spacing and minimum sizes, recognition,
co-branding, print preparation, destination adoption, and native archive/restore
acceptance remain open. The existing brand and Lab completion obligations
remain in force.
