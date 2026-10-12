# quero.

Loja de demonstração em que as compras usam apenas moedas virtuais; não há pagamentos nem venda de produtos reais. A conta, o saldo, as missões, a sacola e a coleção são persistidos no Supabase.

## Configuração

1. No painel do Supabase, abra **SQL Editor** e execute, nessa ordem:
   - [`supabase/migrations/20261011000100_quero_store.sql`](./supabase/migrations/20261011000100_quero_store.sql);
   - [`supabase/migrations/20261012000100_quero_account_management.sql`](./supabase/migrations/20261012000100_quero_account_management.sql), para edição do perfil e cancelamento da conta;
   - [`supabase/migrations/20261013000100_quero_admin.sql`](./supabase/migrations/20261013000100_quero_admin.sql), para o painel, papéis de acesso e catálogo configurável;
   - [`supabase/migrations/20261014000100_quero_mission_recurrence.sql`](./supabase/migrations/20261014000100_quero_mission_recurrence.sql), para recorrência e histórico de resgates de missões;
   - [`supabase/migrations/20261015000100_quero_product_offers.sql`](./supabase/migrations/20261015000100_quero_product_offers.sql), para preços promocionais;
   - [`supabase/migrations/20261016000100_quero_surprise_boxes.sql`](./supabase/migrations/20261016000100_quero_surprise_boxes.sql), para caixas-surpresa;
   - [`supabase/migrations/20261017000100_quero_catalog_visuals.sql`](./supabase/migrations/20261017000100_quero_catalog_visuals.sql), para configurar emoji e cor das categorias e a cor das caixas-surpresa.
   Em um projeto que já tenha recebido alguma migração, execute apenas as migrações que ainda não foram aplicadas, sempre respeitando essa ordem; não é necessário reexecutar as anteriores.
2. No painel, em **Authentication → URL Configuration**, configure a URL publicada do site como **Site URL** e inclua também em **Redirect URLs**:
   - `http://localhost:8000/**` para desenvolvimento local;
   - a URL do GitHub Pages, por exemplo `https://<usuario>.github.io/<repositorio>/**`.
3. Confirme que o provedor **Email** está habilitado em **Authentication → Sign In / Providers**.
4. Em **Settings → Pages**, escolha **GitHub Actions** como fonte de publicação. O workflow publica o site automaticamente ao enviar alterações para `main`; [`index.html`](./index.html) é a entrada.

A URL e a chave **publishable** do projeto Supabase ficam no cliente estático para que o navegador possa conectar. Essa chave é pública por definição: não coloque aqui uma chave `service_role`, senha do banco nem qualquer outra credencial privada. O saldo, as compras, o perfil, o cancelamento da conta e as operações administrativas são processados por funções SQL autenticadas; as tabelas privadas não aceitam gravações diretas do navegador.

## Administração

O painel fica em [`admin.html`](./admin.html), fora da navegação da loja. Ele exige uma conta Supabase com papel `admin` ou `editor`; não basta conhecer o endereço da página.

Para liberar a primeira conta administradora:

1. Crie a conta normalmente pela página da loja e confirme o e-mail, se essa exigência estiver habilitada.
2. No Supabase **SQL Editor**, execute o comando abaixo substituindo o endereço pelo e-mail exato dessa conta:

   ```sql
   insert into public.quero_admin_users (user_id, role)
   select id, 'admin'
   from auth.users
   where lower(email) = lower('seu-email@exemplo.com')
   on conflict (user_id) do update set role = excluded.role;
   ```

3. Abra `admin.html` no endereço publicado e entre com essa conta. Para adicionar editores pelo painel, cada pessoa deve primeiro criar uma conta na loja; depois, informe o e-mail dessa conta na seção **Editores**. Editores podem gerenciar categorias, produtos, missões e pontuação, mas apenas administradores podem conceder ou remover esse acesso.

Produtos, categorias e missões arquivados deixam de aparecer para novas interações, mas seus registros e o histórico de coleção não são apagados. O painel altera recompensas futuras; moedas já recebidas não são recalculadas.

As missões podem ser configuradas para resgate único, diário, semanal ou mensal. Os períodos seguem o horário de Brasília (`America/Sao_Paulo`); a semana começa na segunda-feira. Cada resgate aprovado abre uma comemoração animada e o crédito é validado no banco.

## Executar localmente

Sirva a pasta do projeto por HTTP em vez de abrir o HTML como arquivo. Com Python instalado:

```powershell
python -m http.server 8000
```

Abra `http://localhost:8000`. Configure essa URL na lista de redirecionamentos do Supabase antes de testar confirmação de e-mail.

## Publicação

No GitHub, abra **Settings → Pages** e configure **GitHub Actions** como fonte. O workflow não exige build nem secrets de CI. Depois do primeiro deploy, configure a URL final nas opções de autenticação do Supabase.

## Demonstração de anúncio

A animação é fictícia, não carrega publicidade nem afirma uma visualização verificável. O painel configura a quantidade de moedas e o intervalo entre recompensas por conta. Essa demonstração não deve ser apresentada como anúncio recompensado de um provedor externo.
