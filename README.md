# Interpreter Lab 🧪

**Interpreter Lab** — отдельное экспериментальное приложение для iPhone, визуально повторяющее **Interpreter Live**, но использующее другой принцип перевода.

**Русский ↔ Deutsch** · две кнопки удержания · живая индикация микрофона · тёмный интерфейс · выбор голосов.

### Цепочка обработки

`Apple Speech (ASR) → OpenAI Responses API (готовый текст) → AVSpeechSynthesizer (Apple TTS)`

Вместо непрерывного Realtime/PCM потокового озвучивания после отпускания кнопки приложение сначала получает законченный текст, переводит его, затем произносит. Это позволяет сравнить точность и стабильность с Interpreter Live.

### Сборка и настройка

Подробно: [SETUP.md](SETUP.md).

- XcodeGen: `brew install xcodegen && swift scripts/make-icon.swift && xcodegen generate`
- Иконка LAB генерируется из собственного чёрно-белого изображения `Design/LabIcon512.png`
- Схема: `InterpreterLab`; минимальная iOS: 18.4
- CI: [GitHub Actions](https://github.com/kryukow/interpreter-lab/actions/workflows/build-ios.yml), артефакт `Interpreter-Lab-0.1.0-Unsigned-iPhone`
- Bundle ID: `org.interpreter.lab` — независим от основной программы
- Ключ OpenAI добавляется в настройках приложения и хранится в Keychain
- **В этой версии перевод через платный API, а озвучивание через Apple TTS. Подписка ChatGPT Plus не используется.**

### План эксперимента

После проверки первой сборки на iPhone: обработка пауз и обрывов Apple ASR, сравнение синтезаторов (Apple / OpenAI TTS / локальная модель), измерение задержек и стоимости. Функции, не реализованные в текущем прототипе, не считаются работающими.
