# План: практики безопасности GitHub-интеграции

## Контекст

AI-агент вызывается из комментариев через workflow `.github/workflows/opencode.yml` (триггеры
`issue_comment` и `pull_request_review_comment`). Сейчас из практик безопасности реализована только
фильтрация событий (по телу комментария: `/oc`, `/opencode`). Отсутствуют явная защита от
зацикливания (запуск по собственным комментариям бота исключён лишь неявно) и контроль расходов
(нет таймаутов, лимитов параллельности и дневного бюджета на запуск агента).

Цель — реализовать и «зафиксировать» в проекте все три практики: фильтрацию событий,
защиту от зацикливания и контроль расходов.

## Целевой результат

- Workflow `opencode.yml`:
  - запускается только по комментарию владельца репозитория `ivveta` (не боту и не посторонним);
  - новый вызов на той же ветке/PR отменяет виснущий прогон (concurrency);
  - сессия агента ограничена 30 минутами;
  - перед запуском агента срабатывает гейт дневного бюджета (не более 10 успешных запусков за 24 ч).
- В `AGENTS.md` задокументированы все три практики.

## Изменения

### 1. `.github/workflows/opencode.yml` — защита от зацикливания

- [x] В `if:` job добавить ограничение по автору комментария:

```yaml
    if: |
      github.event.comment.user.login == 'ivveta' &&
      github.event.comment.user.type != 'Bot' &&
      (contains(github.event.comment.body, ' /oc') ||
       startsWith(github.event.comment.body, '/oc') ||
       contains(github.event.comment.body, ' /opencode') ||
       startsWith(github.event.comment.body, '/opencode'))
```

- `login == 'ivveta'` — вызвать агента может только владелец репозитория.
- `type != 'Bot'` — комментарий любого бота (в т.ч. `opencode-agent`), даже с триггер-словом,
  не запускает агента; закрывает эхо-зацикливание.

### 2. `.github/workflows/opencode.yml` — контроль расходов

- [x] **а) concurrency — один агент на ветку/PR, новый вызов отменяет текущий прогон:**

```yaml
concurrency:
  group: opencode-${{ github.ref }}
  cancel-in-progress: true
```

- [x] **б) жёсткий потолок сессии и право листать runs для гейта бюджета:**

```yaml
    timeout-minutes: 30
    permissions:
      id-token: write
      actions: read
      contents: write
      pull-requests: write
      issues: write
```

Явный блок `permissions` сбрасывает остальные скоупы в `none`, поэтому для
бюджет-гейта (список запусков workflow) требуется добавить `actions: read`.

- [x] **в) дневной бюджет — шаг-гейт первым в job (до `checkout`), при превышении job падает:**

```yaml
      - name: Check daily agent budget
        env:
          MAX_RUNS_PER_DAY: '10'
        uses: actions/github-script@v7
        with:
          script: |
            const max = Number(process.env.MAX_RUNS_PER_DAY);
            const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
            const { data } = await github.rest.actions.listWorkflowRuns({
              owner: context.repo.owner,
              repo: context.repo.repo,
              workflow_id: 'opencode.yml',
              created: `>=${since}`,
              per_page: 100,
            });
            const count = data.workflow_runs.filter(
              (r) => r.status === 'completed' && r.conclusion === 'success' && r.run_id !== context.runId
            ).length;
            core.info(`Agent runs in last 24h: ${count}/${max}`);
            if (count >= max) core.setFailed(`Daily agent budget exceeded: ${count} >= ${max}`);
```

### 3. `AGENTS.md` — фиксация практик

- [x] Добавить раздел «Практики безопасности GitHub-интеграции» (после «Общие правила»):

- **Фильтрация событий** — отклик только на `issue_comment` / `pull_request_review_comment`
  с телом, содержащим `/oc` или `/opencode`; вызывать может только владелец `ivveta`.
- **Защита от зацикливания** — исключение авторов-ботов (`type != 'Bot'`) в `if:` workflow;
  concurrency-группа на ветку (`cancel-in-progress`) отменяет виснущий прогон.
- **Контроль расходов** — `timeout-minutes: 30` на сессию агента; дневной бюджет
  `MAX_RUNS_PER_DAY: 10` успешных запусков агента (гейт перед запуском).

## Проверка реализации

- [x] YAML-валидация изменённых файлов.
- [ ] После влития в main (runtime-проверки, вне сферы текущей правки):
  1. `/oc`-комментарий от `ivveta` → job запускается (фильтры владельца/бота не мешают);
  2. комментарий от `opencode-agent` с триггер-словом → job скипается на `if:`,
     платные минуты не тратятся;
  3. временно `MAX_RUNS_PER_DAY: 1` и два вызова подряд → второй падает на гейте,
     агент не запускается; затем вернуть 10;
  4. два комментария подряд в один PR → второй отменяет первый прогон.
- [ ] `make`, `npm run build`, `npm test` не затронуты — меняется только CI.

## Открытые вопросы

- Нет: значения зафиксированы (`MAX_RUNS_PER_DAY=10`, таймаут 30 мин) и при необходимости
  подстраиваются при первом ночном прогоне.

## Реализация

- [x] Выполнена напрямую (правки на 2 файла, запуск сабагента избыточен): реализованы
  пп. 1–3, YAML провалидирован; runtime-проверки (п. 4) — после влития в main.