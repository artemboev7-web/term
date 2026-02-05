# Term — macOS Terminal Emulator

> **Язык общения: Русский.**

Минималистичный терминал для macOS на **Swift + SwiftTerm**.

## Стек

- **Swift 5.9+**
- **SwiftTerm** — терминальный эмулятор от Miguel de Icaza
- **AppKit** — нативный UI macOS

## Сборка и запуск

```bash
# Сборка
swift build

# Запуск
swift run

# Release сборка
swift build -c release
```

## Структура

```
term/
├── Package.swift           # SPM манифест
├── Sources/Term/
│   ├── main.swift          # Entry point
│   └── AppDelegate.swift   # Главный делегат приложения
└── CLAUDE.md
```

## Фичи (planned)

- [ ] Tabs
- [ ] Split panes
- [ ] Настраиваемые горячие клавиши
- [ ] Темы
- [ ] Конфигурационный файл

## SwiftTerm API

```swift
// Создание терминала с локальным процессом
let terminal = LocalProcessTerminalView(frame: rect)
terminal.startProcess(executable: "/bin/zsh", execName: "zsh")

// Настройка
terminal.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
terminal.nativeBackgroundColor = .black
terminal.nativeForegroundColor = .white
```

## Ссылки

- [SwiftTerm GitHub](https://github.com/migueldeicaza/SwiftTerm)
- [SwiftTerm Docs](https://migueldeicaza.github.io/SwiftTermDocs/)
