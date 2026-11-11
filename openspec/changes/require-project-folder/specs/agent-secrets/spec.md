## ADDED Requirements

### Requirement: Ключ проектного провайдера привязан к адресу
Ключ провайдера из проектного слоя SHALL уходить только на адрес, с которым его связал пользователь (design.md change `require-project-folder`, D23). Правило SHALL действовать одинаково для корня процесса и для папки любой сессии. Его проверяет ядро при разрешении конфигурации и функция модели при запросе.

1. **Доверие.** Без доверия проекта (`trusted_projects`) `providers.*` проектных слоёв отбрасываются, как раньше.
2. **Группа целиком из одного слоя.** Группа адреса и аутентификации провайдера — `kind`, `base_url`, `headers`, `api_key_env`, `api_key_secret`. Если проектный слой задаёт любое поле группы провайдера, определённого ниже, группа SHALL браться из проектного слоя целиком. Ссылка на ключ нижнего слоя к адресу проектного слоя НЕ SHALL наследоваться.
3. **Привязка к origin.** Ссылка на ключ в группе из проектного слоя — `api_key_secret`, `api_key_env`, `${secret:…}` и `${ENV}` в `headers` — SHALL разрешаться, только если выполнено одно из условий:
   - (a) ссылка задана в слое `projectLocal` (`config.local.yaml`) доверенного проекта;
   - (b) глобальные слои (`user`, `--config`, окружение, флаги) связывают ту же ссылку с тем же origin (`scheme://host:port`) `base_url`.
4. **Отказ.** Иначе провайдер остаётся в каталоге, а запрос с его моделью SHALL завершаться ошибкой провайдера без HTTP-запроса: `Provider <id> from <file> cannot use <reference>: the key is bound to another address. Move the provider to config.local.yaml or to the user config.`. При загрузке SHALL писаться предупреждение `config.provider.key_unbound {provider, source, reference_kind}`. Значение секрета или переменной НЕ SHALL читаться для такой ссылки и НЕ SHALL попадать в лог, текст ошибки, `configOptions` и диагностику; адрес — только origin.

#### Scenario: Закоммиченный конфиг уводит глобальный ключ на свой адрес
- **WHEN** глобальный слой задаёт провайдера `anthropic` с `api_key_secret: codelab/anthropic` (значение `sk-test-leak-0123456789`), доверенный проект в `config.yaml` задаёт провайдера `relay` с `base_url: https://evil.example` и `api_key_secret: codelab/anthropic`, и сессия этого проекта выбирает модель `relay/m`
- **THEN** HTTP-запроса нет, ход завершается ошибкой `Provider relay from <path> cannot use secret codelab/anthropic: …`, лог содержит `config.provider.key_unbound`, а ни лог, ни ошибка, ни диагностика, ни `configOptions` не содержат `sk-test-leak-0123456789`; хранилище секретов не читалось

#### Scenario: Проект меняет адрес глобального провайдера
- **WHEN** глобальный слой задаёт провайдера `openai` с `base_url: https://api.openai.com` и `api_key_env: OPENAI_API_KEY`, а доверенный `config.yaml` проекта задаёт только `providers.openai.base_url: https://evil.example`
- **THEN** группа провайдера `openai` в сессии проекта — из проектного слоя и не содержит ссылки на ключ; запрос на `https://evil.example` идёт без заголовка авторизации, а переменная `OPENAI_API_KEY` не читалась

#### Scenario: Провайдер «This project only» работает
- **WHEN** мастер записал провайдера `local` с `api_key_secret: codelab/local` в `config.local.yaml` доверенного проекта
- **THEN** сессия проекта получает ключ `codelab/local` при запросе к `local`

#### Scenario: Ссылка, связанная глобально с тем же адресом
- **WHEN** глобальный слой связывает `api_key_secret: codelab/anthropic` с `https://api.anthropic.com`, а `config.yaml` доверенного проекта задаёт провайдера `team` с тем же origin и той же ссылкой
- **THEN** ключ разрешается, запрос к `team` идёт с ним

#### Scenario: Недоверенный проект
- **WHEN** недоверенный проект задаёт любой провайдер со ссылкой на секрет
- **THEN** провайдер отброшен с `config.project.untrusted_key`, секрет не читался
