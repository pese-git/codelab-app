// Тесты allowlist публикации (tasks.md add-astro-site, 3.1; D3, D11;
// project-site «Публикуемые источники документации»).
import { describe, expect, it } from 'vitest';

import { isPublished, publishPatterns } from '../src/lib/publish';

describe('publishPatterns', () => {
  it('содержит все шаблоны спецификации project-site', () => {
    expect(publishPatterns).toEqual(
      expect.arrayContaining([
        'docs/user/**/*.md',
        'docs/ops/**/*.md',
        'apps/*/README.md',
        'apps/*/doc/**/*.md',
        'packages/*/*/README.md',
        'packages/*/*/doc/**/*.md',
      ]),
    );
  });
});

describe('isPublished', () => {
  it.each([
    'docs/user/README.md',
    'docs/user/configuration.md',
    'docs/user/sub/deep.md',
    'docs/ops/README.md',
    'docs/ops/codelab-home.md',
    'apps/codelab_cli/README.md',
    'apps/codelab_cli/doc/user-guide.md',
    'apps/codelab_desktop/doc/sub/x.md',
    'apps/codelab_new/doc/intro.md',
    'packages/dart/codelab_setup/README.md',
    'packages/dart/codelab_setup/doc/config.md',
    'packages/flutter/codelab_ui/README.md',
    'packages/flutter/codelab_ui/doc/sub/widgets.md',
  ])('публикует %s', (path) => {
    expect(isPublished(path)).toBe(true);
  });

  it.each([
    // AGENTS.md исключён везде, даже внутри doc/ (D3).
    'apps/codelab_cli/AGENTS.md',
    'apps/codelab_cli/doc/AGENTS.md',
    'packages/dart/codelab_setup/doc/AGENTS.md',
    'docs/user/AGENTS.md',
    'AGENTS.md',
    // Каталоги вне списка (D3, D11).
    'docs/architecture/testing.md',
    'docs/backlog/smoke-2026-10-30.md',
    'docs/protocols/acp/protocol/17-Schema.md',
    'docs/design/claude-design/README.md',
    'docs/integrations/claude-code.md',
    'docs/codelab-spec.md',
    'openspec/specs/project-site/spec.md',
    'openspec/changes/add-astro-site/design.md',
    // Корень и прочее.
    'README.md',
    'CHANGELOG.md',
    'apps/codelab_cli/CHANGELOG.md',
    'apps/codelab_cli/lib/README.md',
    'packages/dart/README.md',
    'packages/dart/codelab_setup/test/README.md',
    'packages/dart/codelab_agent_core/prompts/system.md',
    // Только .md.
    'docs/user/image.png',
    'apps/codelab_desktop/doc/images/command-palette.png',
    'docs/user/README.markdown',
  ])('не публикует %s', (path) => {
    expect(isPublished(path)).toBe(false);
  });
});

describe('isPublished: сегменты пути', () => {
  it.each([
    'docs/user/../backlog/x.md',
    'docs/user/./x.md',
    'docs/user//x.md',
    'apps/../docs/backlog/README.md',
    'packages/dart/../../docs/architecture/README.md',
  ])('%s — не опубликован', (path) => {
    expect(isPublished(path)).toBe(false);
  });
});
