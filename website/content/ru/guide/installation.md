---
title: "Установка и сборка"
description: "Установка StrokeMouse или сборка из исходников. macOS 14+, CLI, Xcode, подпись и тесты."
keywords: "установка StrokeMouse,сборка из исходников,xcodebuild,подпись,macOS 14"
---

# Установка и сборка

Рекомендуемый способ — Homebrew. Сборки **Apple Silicon / Intel** также можно взять на [странице загрузок](/ru/download). Чтобы собрать самостоятельно, следуйте шагам ниже.

## Требования

| Пункт | Требование |
|------|-------------|
| ОС | macOS 14 Sonoma или новее |
| Сборка разработки | Xcode 16+ |
| Генерация проекта | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) |

## Homebrew (рекомендуется)

Установка из [поддерживаемого проектом Licoy Homebrew Tap](https://github.com/Licoy/homebrew-tap):

```bash
brew install --cask licoy/tap/strokemouse
```

StrokeMouse также обновляется из приложения. Чтобы Homebrew проверил и поставил обновление:

```bash
brew upgrade --cask --greedy strokemouse
```

При удалении настройки по умолчанию сохраняются. Добавьте `--zap`, чтобы удалить и их:

```bash
brew uninstall --cask strokemouse
brew uninstall --cask --zap strokemouse
```

Homebrew и ручная загрузка используют одни и те же пакеты выпуска, поэтому замечания про Gatekeeper и Универсальный доступ при первом запуске относятся к обоим способам.

## Клонирование

```bash
git clone https://github.com/Licoy/StrokeMouse.git
cd StrokeMouse
```

## Рекомендуется: сборка из CLI

Стабильный путь `output/StrokeMouse.app` снижает повторные запросы Универсального доступа.  
Debug отображается как **StrokeMouse Dev** (Bundle ID `com.strokemouse.app.dev`) и может быть разрешён рядом с выпускным **StrokeMouse**:

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app (доступ: StrokeMouse Dev)
./scripts/build.sh --open    # открыть по готовности
./scripts/build.sh --release # Release (то же имя / Bundle ID, что у выпускных сборок)
```

После изменения `project.yml` или добавления/удаления исходников:

```bash
./scripts/generate_project.sh
```

## Запуск в Xcode

```bash
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

Scheme **StrokeMouse** → Run.

## Подпись кода

| Пункт | Значение |
|------|--------|
| Bundle ID | Release: `com.strokemouse.app`; Debug: `com.strokemouse.app.dev` (имя StrokeMouse Dev) |
| Идентичность разработки | **`StrokeMouse Dev`** в связке ключей (самоподписанная; локальные сборки) |
| Идентичность Release | **`StrokeMouse Release`** самоподписанная + Hardened Runtime (стабильная идентичность; **пользователи не ставят сертификат**) |
| Ad-hoc | `CODE_SIGN_IDENTITY="-" ./scripts/build.sh` или package (только smoke; **доступ не переживает обновления**) |
| Нотаризация | Сейчас нет нотаризации Apple / Developer ID |

::: warning
Если Gatekeeper блокирует GitHub Release при первом запуске, нажмите Control и щёлкните приложение, выберите «Открыть», либо Системные настройки → Конфиденциальность и безопасность → Всё равно открыть.

**Универсальный доступ**: официальные пакеты используют стабильную самоподписанную идентичность, поэтому **обновления в приложении с тем же сертификатом обычно сохраняют разрешение**. Переход со старых ad-hoc сборок или смена сертификата требуют **одного** повторного разрешения. Конечные пользователи сертификат издателя **не устанавливают**.
:::

## Артефакты выпуска

```bash
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

Каждая архитектура даёт ZIP, TAR.GZ и DMG. ZIP также питает обновления Sparkle. Версии и теги описаны в `RELEASING.md` в корне репозитория.

## Тесты

```bash
xcodebuild -scheme StrokeMouse -configuration Debug test
```

## Зависимости

- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) — запуск при входе
- [Sparkle](https://github.com/sparkle-project/Sparkle) — подпись обновлений и установка в приложении
- Система: `CGEventTap`, Универсальный доступ, по желанию Apple Events

## Дальше

После успешной сборки перейдите к [Доступу](./permissions) и [Быстрому старту](./getting-started).
