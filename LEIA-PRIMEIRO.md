# Água de Coco Realeza — Vercel + Supabase

Esta versão usa Next.js, hospedagem Vercel e PostgreSQL com autenticação do Supabase. Mantém a interface verde, as imagens de coco e garrafa, a ordenação dos produtos, o carrinho, Pix/dinheiro/débito/crédito, histórico, fechamento e relatório de 58 mm.

## O que foi corrigido

O build agora é `next build --webpack` e gera `.next/routes-manifest.json`. A versão Vinext/Cloudflare e o login via cabeçalhos do ChatGPT foram substituídos. A configuração de Vercel está no arquivo `vercel.json`. Não coloque `dist` como saída.

## 1. Criar o banco e a conta

1. Crie sua conta em https://supabase.com e um projeto novo. Guarde a senha do banco em local seguro; ela não é a senha de entrada do caixa.
2. No SQL Editor, cole e execute todo o conteúdo de `supabase/schema.sql` uma vez. Esse arquivo cria tabelas, permissões, auditoria e funções. Use um projeto novo; não apague tabelas existentes para reaplicá-lo.
3. Em Authentication → Users, crie sua usuária com seu e-mail e uma senha forte. Confirme o e-mail pelo painel se disponível ou pelo fluxo enviado pelo serviço.
4. Desative novos cadastros públicos nas configurações de autenticação. Não há botão de cadastro no app.
5. Nas configurações de API/Connect do projeto, copie a URL do projeto e a chave pública anon ou publishable. **Não use a chave service_role/secret.**

O banco identifica o usuário pela sessão validada do Supabase. As tabelas têm proteção por usuário; PC e Samsung devem entrar com a mesma conta para ver o mesmo caixa. Não há equipe com usuários distintos compartilhando dados nesta versão.

## 2. Configurar a Vercel

No projeto Vercel conectado ao repositório `lais153/Agua-De-Coco`:

- Framework Preset: **Next.js**.
- Root Directory: a pasta que contém `package.json`. Se os arquivos estão na raiz do GitHub, deixe vazio/padrão.
- Node.js: **24.x**.
- Install Command: `pnpm install --frozen-lockfile`.
- Build Command: `pnpm run build`.
- Output Directory: `.next` (ou padrão do Next.js). Remova qualquer configuração antiga de `dist`.
- Environment Variables: adicione `SUPABASE_URL` e `SUPABASE_ANON_KEY` com os valores do seu projeto para Production e, se for testar prévias, Preview.

Depois de enviar as mudanças ao GitHub, faça um Redeploy sem reaproveitar o cache antigo. Alterar variáveis também exige um novo deploy.

Sem as variáveis, o site mostra uma tela explicando a configuração pendente e não permite registrar vendas. O build não depende de ter acesso ao banco nem de credenciais.

## 3. Abrir no PC

Instale Node.js 24 e o gerenciador informado em `package.json`:

```powershell
npm install -g pnpm@11.25.0
pnpm install
```

Copie `.env.example` para `.env.local` e preencha as duas variáveis com as mesmas usadas na Vercel. Não envie `.env.local` ao GitHub.

```powershell
pnpm dev
```

Abra o endereço mostrado no terminal, normalmente http://localhost:3000. Mesmo no PC, esta versão usa o banco Supabase configurado: use uma conta de teste ou um projeto separado para testes. Não existe mais banco SQLite de teste nem entrada automática de demonstração.

Verificações:

```powershell
pnpm test
pnpm typecheck
pnpm build
```

## 4. Enviar as mudanças

A pasta de trabalho existente foi atualizada, preservando `.git` e o endereço do seu repositório. Revise as alterações e execute:

```powershell
git add .
git commit -m "Adapta caixa para Vercel e Supabase"
git push origin main
```

Não é necessário forçar o envio para esta atualização. Se o terminal disser que a branch está divergente, não use `--force` sem conferir o histórico.

## Antes de usar com vendas reais

Entre com a mesma conta no PC e no Samsung. Cadastre um produto de teste, salve uma venda, recarregue e confira no outro aparelho. Teste edição, exclusão, exportação e fechamento. Um fechamento bloqueia aquela data; prefira um projeto Supabase separado para testar o fechamento completo de hoje. Na aba Fechamento, Reabrir dia permite continuar e fechar novamente. O relatório anterior fica na auditoria; um novo relatório só é liberado depois do próximo fechamento.

As operações de escrita são transacionais no PostgreSQL e serializadas por usuário. Preços e totais são calculados no banco. Reenvios do mesmo identificador não duplicam a venda. Exclusões são lógicas, com auditoria. As sessões usam cookies HttpOnly e são renovadas pelo servidor; caso a sessão expire ou seja revogada, entre novamente. Cabeçalhos de identidade do visitante não autenticam ninguém.

## Produtos e dados antigos

Os 6 produtos ativos da prévia, com seus preços e ordem, estão preservados em `lib/initial-products.json` e são cadastrados uma única vez quando uma conta abre um banco vazio. Dados e vendas antigas não migram automaticamente. Foi salvo um backup independente da prévia antes desta mudança (6 produtos e nenhuma venda). Antes de abandonar a prévia, exporte **Backup completo**. O arquivo guarda produtos, vendas, fechamentos e auditoria. Não envie backups financeiros ao GitHub. Você pode conferir e editar os produtos na aba Produtos; o cadastro inicial não substitui produtos que já existam no banco. Uma importação de vendas antigas deve validar o arquivo e os totais antes de inserir no novo banco. Não há restauração/importação automática nesta versão.

O app continua com as imagens fornecidas e identifica os nomes de garrafa, inclusive as grafias cadastradas GARAFFA e GAFARRA. Use as setas na aba Produtos para escolher a ordem; ela é mantida na tela Vender.

## Backup e impressão

Baixe Backup completo em JSON ao fim do dia e guarde uma cópia fora do celular. CSV é para consulta das vendas ativas. Não há backup agendado: armazenamento online e exportação manual não são garantia contra toda perda. O projeto depende da disponibilidade, limites e retenção do plano contratado no Supabase e na Vercel.

O pedido ainda não confirmado só existe na tela. Sem internet, mantenha a página aberta e tente salvar de novo; fechar a página pode perder o pedido pendente. Vendas confirmadas ficam no banco online.

O relatório gerencial de 58 mm só está disponível após fechar o dia e pode ser reimpresso. Não é documento fiscal. O botão usa o diálogo de impressão do sistema. No PC, instale o driver da impressora e configure papel/margens. No Samsung, Bluetooth depende do modelo e de um serviço de impressão ou app do fabricante. Parear a impressora não garante impressão pelo Chrome; comandos ESC/POS diretos não estão implementados.

## Referências

- https://vercel.com/docs/builds/configure-a-build
- https://supabase.com/docs/guides/database/functions
- https://supabase.com/docs/guides/database/postgres/row-level-security


## Atualização: reabrir dia
Bancos existentes precisam executar uma vez supabase/migrations/002_reabrir_dia.sql. O botão Reabrir dia remove apenas o bloqueio da data e preserva o fechamento anterior na auditoria, sem apagar vendas. Um novo fechamento recalcula o relatório. A função já foi aplicada no banco desta instalação.


## Abertura e conferência de dinheiro
Antes de vender, informe o dinheiro inicial de troco e clique Abrir caixa. Pode ser 0,00. Esse dinheiro não é faturamento. No fechamento, informe o dinheiro contado: esperado = valor inicial + vendas em dinheiro. Pix, débito e crédito permanecem separados. O relatório mostra inicial, esperado, contado e sobra/falta. Reabrir mantém a abertura original e exige nova contagem ao fechar de novo. Não há registro de retiradas/suprimentos nesta versão; a conta pressupõe que não ocorreram movimentações de dinheiro fora das vendas.
Bancos existentes executam supabase/migrations/003_abertura_caixa.sql uma vez após a migração 002. Essa atualização já foi aplicada e testada no banco desta instalação. O teste transacional supabase/test-abertura.sql reverte todos os registros de teste.

