# SwiftSymbolKit

Toolkit for mangled Swift symbol parsing and printing.

This repo is a manual fork of the incredible repo [mattgallagher/CwlDemangle](https://github.com/mattgallagher/CwlDemangle).

### Architecture

| Module | Responsibility |
| --- | --- |
| `SwiftSymbolCLI` | Provides the command-line interface. |
| `SwiftSymbolIndexStore` | Builds, queries, merges, and exports the unified symbol index. |
| `SwiftIndexing` | Defines shared declaration, relationship, symbol record, and diagnostic models. Extracts declarations and evidence from mangled symbols, existing Swift interfaces, the dyld shared cache, and compiler dumps. |
| `SwiftDemangle` | Provides the underlying mangled symbol parser. |

Exported symbols from TBD files define the linkable surface of the generated interface. Other sources enrich and cross-check those symbols with information that mangled names cannot fully preserve, such as default arguments, generic parameter names, type aliases, and protocol metadata.

Swift interface, dyld shared cache, and compiler dump adapters are currently placeholders.

### Credits

- [mattgallagher/CwlDemangle](https://github.com/mattgallagher/CwlDemangle)
