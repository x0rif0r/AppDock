"""Render only public catalog fields, never an account purchase history."""
import json
import pathlib

root = pathlib.Path(__file__).resolve().parents[1]
data = json.loads((root / 'catalog/apps.json').read_text())
text = '''# Справочник приложений

Известные приложения: доступные и исчезнувшие из магазина. Это не список покупок и не гарантия загрузки. `reported` — сведения из публикаций; `metadata_only` — сверены идентификаторы, но официальность отдельно не подтверждена; `confirmed` — связь с брендом подтверждена первичным источником. `unknown` означает, что текущая доступность ещё не установлена. Не все записи являются удалёнными приложениями.

| Семейство | Название | App Store ID | Bundle ID | Проверка | Доступность | Источник |
|---|---|---:|---|---|---|---|
'''
for app in data['apps']:
    values = [app['family'], app['name'], str(app['id']), app['bundleID'] or '—',
              app['verification'], app['distribution'], f"[источник]({app['sources'][0]})"]
    text += '| ' + ' | '.join(v.replace('|', '\\|') for v in values) + ' |\n'
text += '\n## Идентификаторы ещё уточняются\n\nЭти приложения наблюдались на устройстве, но точное соответствие числовому App Store ID пока не подтверждено. Они не используются для автоматического скачивания.\n\n| На iPhone | Имя в метаданных | Bundle ID | App Store ID |\n|---|---|---|---|\n'
unresolved = json.loads((root / 'catalog/unresolved.json').read_text())
for app in unresolved['apps']:
    text += f"| {app['name']} | {app['storeName']} | {app['bundleID']} | Не подтверждён |\n"
text += '\nПредложения принимаются через [форму заявки](https://github.com/x0rif0r/AppDock/issues/new?template=app.yml) или Pull Request по [правилам](../CONTRIBUTING.md). Не прикладывайте IPA, Apple ID, лицензии аккаунтов, UDID или серийные номера.\n'
(root / 'catalog/README.md').write_text(text)
