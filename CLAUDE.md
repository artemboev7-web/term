# Term — macOS Terminal Emulator

> **Язык общения: Русский.**

Минималистичный терминал для macOS на **Swift + SwiftTerm**.

## Фичи

- ✅ **Tabs** — native macOS window tabs (⌘T новая вкладка)
- ✅ **Split Panes** — горизонтальный/вертикальный split (⌘D / ⌘⇧D)
- ✅ **Preferences** — настройки шрифта, темы, shell
- ✅ **Themes** — Dark / Light
- ✅ **Full Menu Bar** — все стандартные меню macOS
- ✅ **Zoom** — ⌘+/⌘-/⌘0

## Горячие клавиши

| Комбинация | Действие |
|------------|----------|
| ⌘N | Новое окно |
| ⌘T | Новая вкладка |
| ⌘D | Split горизонтально |
| ⌘⇧D | Split вертикально |
| ⌘W | Закрыть вкладку |
| ⌘⇧W | Закрыть окно |
| ⌘] / ⌘[ | Следующая/предыдущая вкладка |
| ⌘+ | Увеличить шрифт |
| ⌘- | Уменьшить шрифт |
| ⌘0 | Сбросить размер шрифта |
| ⌘K | Очистить буфер |
| ⌘, | Настройки |
| ⌃⌘F | Полноэкранный режим |

## Стек

- **Swift 5.9+**
- **SwiftTerm** — терминальный эмулятор от Miguel de Icaza
- **AppKit** — нативный UI macOS

## Структура

```
term/
├── Package.swift
├── Sources/Term/
│   ├── App/
│   │   ├── TermApp.swift           # Entry point + Menu setup
│   │   └── AppDelegate.swift       # Window management
│   ├── Windows/
│   │   ├── TerminalWindowController.swift  # Tab management
│   │   └── PreferencesWindowController.swift
│   ├── Views/
│   │   ├── TerminalViewController.swift    # Split pane management
│   │   └── TerminalPaneView.swift          # SwiftTerm wrapper
│   └── Settings/
│       └── Settings.swift          # UserDefaults + Themes
└── CLAUDE.md
```

## Сборка и запуск

```bash
# Сборка
swift build

# Запуск
swift run

# Release сборка
swift build -c release

# Собрать .app bundle (TODO)
# swift build -c release && ...
```

## TODO

- [ ] .app bundle с Info.plist и иконкой
- [ ] Сохранение/восстановление сессий
- [ ] Больше тем (Dracula, Solarized, Nord)
- [ ] Поиск в буфере (⌘F)
- [ ] Настраиваемые hotkeys
- [ ] URL detection и клики
- [ ] Profile support (разные настройки для разных сессий)

## SwiftTerm API

```swift
// Терминал с локальным процессом
let terminal = LocalProcessTerminalView(frame: rect)
terminal.startProcess(executable: "/bin/zsh", args: ["-l"])

// Делегат для событий
terminal.processDelegate = self  // processTerminated, sizeChanged, setTerminalTitle

// Настройка
terminal.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
terminal.nativeBackgroundColor = .black
terminal.nativeForegroundColor = .white
terminal.caretColor = .cyan
```

## MCP Servers

### Глобальные (см. `~/.claude/CLAUDE.md`)
- `mcp__docs-mcp__*` — поиск по документации (:9100)
- `mcp__memory__*` — персистентная память (:9101)
- `mcp__brave-search__*` — веб-поиск Brave (:9102)
- `mcp__sequential-thinking__*` — сложные рассуждения (:9103)
- `mcp__ast-grep__*` — AST поиск по коду (:9104)
- `mcp__browser-agent__*` — браузерная автоматизация (:9105)
- `mcp__vm-monitor__*` — мониторинг VM (:9106)
- `mcp__context7__*` — документация библиотек (:9107)
- `mcp__claude-context__*` — семантический поиск по коду (:9108)
- `mcp__lsp__*` — Language Server Protocol (:9109)
- `mcp__exa__*` — AI-powered веб-поиск Exa (:9111)

## Ссылки

- [SwiftTerm GitHub](https://github.com/migueldeicaza/SwiftTerm)
- [SwiftTerm Docs](https://migueldeicaza.github.io/SwiftTermDocs/)
