# quero.

Loja de demonstração em que as compras usam apenas moedas virtuais; não há pagamentos nem venda de produtos reais. A conta, o saldo, as missões, a sacola e a coleção são persistidos no Supabase.

## Configuração

1. No painel do Supabase, abra **SQL Editor** e execute, nessa ordem, [`supabase/migrations/20261011000100_quero_store.sql`](./supabase/migrations/20261011000100_quero_store.sql) e [`supabase/migrations/20261012000100_quero_account_management.sql`](./supabase/migrations/20261012000100_quero_account_management.sql). A segunda migração habilita a edição do apelido e o cancelamento da conta.
2. No painel, em **Authentication → URL Configuration**, configure a URL publicada do site como **Site URL** e inclua também em **Redirect URLs**:
   - `http://localhost:8000/**` para desenvolvimento local;
   - a URL do GitHub Pages, por exemplo `https://<usuario>.github.io/<repositorio>/**`.
3. Confirme que o provedor **Email** está habilitado em **Authentication → Sign In / Providers**.
4. Em **Settings → Pages**, escolha **GitHub Actions** como fonte de publicação. O workflow publica o site automaticamente ao enviar alterações para `main`; [`index.html`](./index.html) é a entrada.

A URL e a chave **publishable** do projeto Supabase ficam no cliente estático para que o navegador possa conectar. Essa chave é pública por definição: não coloque aqui uma chave `service_role`, senha do banco nem qualquer outra credencial privada. O saldo, as compras, o perfil e o cancelamento da conta são processados por funções SQL autenticadas; as tabelas privadas não aceitam gravações diretas do navegador.

## Executar localmente

Sirva a pasta do projeto por HTTP em vez de abrir o HTML como arquivo. Com Python instalado:

```powershell
python -m http.server 8000
```

Abra `http://localhost:8000`. Configure essa URL na lista de redirecionamentos do Supabase antes de testar confirmação de e-mail.

## Publicação

No GitHub, abra **Settings → Pages** e configure **GitHub Actions** como fonte. O workflow não exige build nem secrets de CI. Depois do primeiro deploy, configure a URL final nas opções de autenticação do Supabase.

## Demonstração de anúncio

A animação é fictícia, não carrega publicidade nem afirma uma visualização verificável. A função do banco limita o crédito de 100 moedas a uma vez por conta por hora. Essa demonstração não deve ser apresentada como anúncio recompensado de um provedor externo.
