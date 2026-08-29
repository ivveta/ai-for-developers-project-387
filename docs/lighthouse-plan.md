# План: регулярная Lighthouse-проверка продакшена

## Контекст

Проект использует GitHub Actions (`.github/workflows/ci.yml` и др.). Прод развёрнут на Render:
`https://ai-for-developers-project-386-tchb.onrender.com/`. Публичные маршруты SPA (без авторизации):
`/` (Home), каталог встреч, форма брони, включая `/admin` (управление видами брони).

## Целевой результат

Новый workflow `.github/workflows/lighthouse.yml`:
- запускается по расписанию (cron, ночью) и вручную (`workflow_dispatch`);
- прогоняет Lighthouse CI (LHCI) по опубликованному прод-адресу;
- сохраняет HTML-отчёт как артефакт на вкладке Actions;
- при падении порогов создаёт issue со списком нужных правок.

## Задачи (маппинг на требования)

| Требование | Что делаем |
|---|---|
| Запуск по расписанию | `on: schedule` (cron) + `workflow_dispatch` в workflow |
| Ручной запуск | триггер `workflow_dispatch` (кнопка Run workflow) |
| Lighthouse CLI + отчёт | `@lhci/cli` — `lhci autorun` с конфигом `lighthouserc.json` |
| Отчёт сохраняется для утра | `actions/upload-artifact` (HTML-отчёт + JSON-метрики) |
| Фиксация нужных правок | шаг, который при пороге ниже бюджета создаёт issue с перечнем метрик |

## Файлы

### 1. Новый: `lighthouserc.json` (в корне репозитория)

Конфиг LHCI:
- `ci.collect`: `url` = прод-адрес + ключевые публичные маршруты (главная, каталог/бронирование, `/admin`),
  `numberOfRuns: 3`, `settings.chromeFlags` (headless), desktop/mobile viewport по необходимости.
- `ci.assert`: мягкие (soft/report-only) пороги по Performance/Accessibility/Best Practices/SEO,
  чтобы не валить ночной прогон на старте, но ловить регрессии.
- `ci.upload`: `target: filesystem`, отчёт в `.lighthouseci/`.

### 2. Новый: `.github/workflows/lighthouse.yml`

```yaml
name: lighthouse

on:
  schedule:
    - cron: '0 1 * * *'   # каждую ночь в 01:00 UTC
  workflow_dispatch:

jobs:
  lighthouse:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write        # чтобы создавать issue с правками
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: npm }
      - run: npm ci
      - run: npx lhci autorun     # собирает .lighthouseci/ (HTML+JSON)
      # загрузка отчёта для утреннего просмотра
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: lighthouse-report
          path: .lighthouseci/
      # фиксация правок при падении порогов
      - name: Open issue on budget failure
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            # парсит .lighthouseci/*.json, формирует таблицу метрик,
            # пишет body и создаёт issue (или комментирует в существующем)
```

### 3. Правки: `package.json` (корень)

- добавить devDependency `@lhci/cli`;
- добавить скрипт `"lighthouse": "lhci autorun"` для локального запуска и единообразного вызова из CI.

### 4. Правки: `.gitignore`

- добавить `.lighthouseci/` — локальная папка отчётов не коммитится;
  в CI артефакт всё равно заливается (`actions/upload-artifact` работает даже с игнорируемыми путями).

## Проверка реализации

- `npx lhci autorun` локально собирает отчёт без ошибок;
- `npm test` / `npm run build` не сломаны (workflow не трогает код приложения);
- на вкладке Actions → `lighthouse` есть ручной запуск по кнопке Run workflow;
- артефакт `lighthouse-report` содержит HTML-отчёт (`index.html`);
- «фиксация правок» проверяется временным занижением порога (сработает issue), затем порог возвращается.

## Открытые вопросы к реализации

- Точные публичные маршруты для обхода (уточнить по `frontend/src/App.tsx`); если часть недоступна на проде без бэка — ограничиться `/`.
- Стартовые значения порогов: сначала soft/report-only, потом поджать по реальным цифрам.
- Токен для issue: встроенный `GITHUB_TOKEN`, доп. секреты не нужны.

## Реализация

По правилам проекта задачу «выполни план» с готовым файлом `*-PLAN.md` реализует сабагент `plan-implementer`.
