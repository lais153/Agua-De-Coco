# Água de Coco Realeza

Projeto para editar no **Visual Studio Code** no PC e usar no Samsung pelo navegador depois da publicação.

## Abrir no editor

1. Extraia o ZIP inteiro para uma pasta do computador.
2. No Visual Studio Code, escolha **Arquivo → Abrir Pasta** e selecione `agua-de-coco-realeza`.
3. Você também pode abrir o arquivo `agua-de-coco-realeza.code-workspace`.

O VisuAlg é outro programa; este projeto usa Visual Studio Code.

## Preparar o PC

Instale Node.js compatível com o requisito do `package.json` (22.13 ou superior) e Git. Abra um novo terminal no editor após instalar.

No terminal, execute:

```powershell
npm install --global pnpm@11.25.0
pnpm install
pnpm build
pnpm db:local
pnpm dev
```

Abra o endereço local mostrado no terminal, normalmente `http://localhost:5173`. O ambiente local simula uma conta de teste no fluxo de entrada. Se necessário, abra `http://localhost:5173/signin-with-chatgpt?return_to=/`.

**O banco local serve para testes. Ele não sincroniza com o Samsung e não é o banco online. Não registre vendas reais antes da publicação e validação.** Não apague `.wrangler/state` se quiser manter os testes.

## Onde editar

- `app/caixa.tsx`: telas, carrinho e interações.
- `app/globals.css`: cores verdes e aparência para PC/celular.
- `app/api/caixa/route.ts`: validação e gravação no banco.
- `db/schema.ts`: estrutura dos dados.
- `drizzle/`: migrações do banco; preserve migrações já aplicadas.

O coco fechado com canudo é desenhado na interface. Os produtos começam vazios porque os nomes e valores antigos não estavam disponíveis no histórico recuperado. Cadastre os valores reais na aba Produtos.

## Verificar

```powershell
pnpm test
pnpm typecheck
pnpm build
```

O teste cobre salvamento, repetição sem duplicação, preços calculados no servidor, quantidades, conflito de edição, exclusão lógica, totais de fechamento, bloqueio após fechar, separação por usuário e autenticação. Isso não substitui testar a publicação e a impressora física.

## Colocar no GitHub

No controle de código do VS Code, inicie um repositório, revise os arquivos e faça o primeiro commit. Publique em um repositório privado da sua conta. Também é possível usar Git no terminal:

```powershell
git init
git add .
git commit -m "Inicia aplicativo Agua de Coco Realeza"
```

Depois associe o repositório criado na sua conta do GitHub. Nenhum envio ao GitHub foi realizado nesta entrega.

O `.gitignore` exclui dependências, banco de teste, arquivos temporários e variáveis locais. Nunca envie senhas, tokens, backups financeiros ou arquivos `.env`. O GitHub guarda o código; as vendas ficam no banco.

## Publicação e banco online

Esta versão está preparada para **Sites + Cloudflare D1**, com acesso privado pela conta ChatGPT. A entrada não é uma senha própria do aplicativo. A pasta `.openai/hosting.json` contém a identificação do Site já registrado nesta conversa; preserve-a para continuar nesse mesmo Site. Ele ainda não foi publicado nesta entrega.

Para publicar, é necessário compilar, sincronizar o código pelo fluxo de publicação do Sites, aplicar as migrações no D1 online e confirmar a publicação privada. Só subir o código no GitHub ou abrir no VS Code não executa essas etapas.

Outra hospedagem exige adaptar o acesso, o banco e a implantação. Os cabeçalhos de identidade deste código são confiáveis apenas atrás da autenticação do Sites; não exponha este servidor diretamente na internet confiando em cabeçalhos enviados pelo visitante.

Depois de publicar: entre com a mesma conta no PC e no Samsung, cadastre um produto, faça uma venda de teste, recarregue e confira no outro aparelho. Verifique o backup e o fechamento de uma data de teste antes de usar como caixa real. No Samsung, adicione o endereço publicado à tela inicial pelo menu do Chrome.

## Salvamento e backup

A venda só é confirmada depois da resposta do banco. Falhas mantêm o pedido na tela enquanto a página continua aberta; não existe fila offline persistente. Fechar ou recarregar antes de salvar pode perder o pedido ainda não confirmado. É preciso internet para trabalhar com o banco online.

O mesmo pedido reenviado mantém seu identificador para evitar duplicação. Edições verificam a versão da venda, e dias fechados bloqueiam novas vendas e alterações. Exclusões preservam o registro e a auditoria no banco.

Em Histórico ou Fechamento, **Backup completo** baixa JSON com produtos, vendas, fechamentos e auditoria. **Exportar CSV** baixa as vendas ativas para consulta. Guarde cópias fora do navegador, de preferência após cada dia. Não há backup agendado nem restauração automática implementada; restauração exige importar e validar o JSON no banco com ajuda técnica. Os dados da versão HTML antiga não são recuperados automaticamente.

## Impressão 58 mm

O relatório gerencial fica disponível somente depois do fechamento; não há impressão a cada venda. É possível reimprimir um fechamento. O relatório não tem valor fiscal.

O botão abre o diálogo de impressão do sistema. Configure papel de 58 mm, margens mínimas e desative cabeçalhos/rodapés. O resultado depende da impressora e do driver.

Bluetooth não é garantido pelo navegador. No PC, a impressora precisa ser reconhecida pelo sistema com driver compatível. No Samsung, pode ser necessário um serviço de impressão ou aplicativo do fabricante. Impressoras Bluetooth que só recebem comandos ESC/POS podem exigir uma integração específica que esta versão não inclui. O pareamento Bluetooth sozinho não garante que a impressora apareça no Chrome. Teste com o modelo físico antes de depender dela no caixa.

## Organizar os produtos
Na aba Produtos, use as setas para cima e para baixo. A ordem fica no banco e vale também na tela Vender. Em instalações anteriores, aplique a nova migração 0001_product_order.sql antes de usar a versão atualizada.

