# Conferidor de Faturas — Web V1

Projeto **independente** do APK atual. Não alterar o repositório do APK nem sua branch Beta.

## O que já funciona
- Login e criação de contas por e-mail e senha (Supabase Auth).
- Criação de grupo e convite por código; dois usuários podem entrar no mesmo grupo.
- Despesas individuais: somente proprietário visualiza e altera.
- Despesas compartilhadas: integrantes do grupo visualizam e alteram.
- Classificações individuais ou do grupo.
- Cartão de crédito, Pix e dinheiro; à vista ou parcelado (até 60 vezes).
- Conta fixa: gera 3, 6, 12, 24 ou 36 ocorrências mensais.
- Vencimento por ocorrência, situação pago/pendente, filtro mensal e tipo.
- Exclusão de uma ocorrência e alteração do status de pagamento.

## Limitações conscientes da V1
- Contas fixas geram ocorrências antecipadas; **ainda não há edição de valores** nem renovação automática após o horizonte escolhido.
- Não há integração com PDFs, cartões bancários, APK, exportação Excel ou dashboard avançado.
- Não há rateio percentual nem histórico de auditoria das edições compartilhadas.
- O código de convite dá acesso ao grupo: compartilhe somente com a pessoa desejada.
- Valor do parcelamento é dividido em centavos; o total da compra não é somado como lançamento adicional.
- O filtro Todas mostra somente despesas individuais próprias e compartilhadas acessíveis, nunca individuais de outra pessoa.

## Configuração pelo GitHub no celular

### 1. Criar projeto separado
1. No GitHub, crie repositório **privado** novo `conferidor-web` (não reutilize `Conferidor-faturas`).
2. Extraia este ZIP no celular e envie **todos os arquivos mantendo as pastas**. Se o GitHub no celular não permitir subir pastas, use `Add file > Create new file` e digite cada caminho, por exemplo `lib/main.dart`, colando o conteúdo.
3. Branch principal `main` apenas do repositório novo.

### 2. Criar Supabase
1. Crie um projeto em https://supabase.com/dashboard.
2. Em `SQL Editor`, abra `supabase/schema.sql` e execute o conteúdo **uma vez** em projeto novo.
3. Em `Authentication > Providers > Email`, habilite e-mail/senha. Configure confirmação de e-mail conforme preferir (recomendado manter confirmação habilitada).
4. Em `Project Settings > API` (ou `Connect`, dependendo da interface), copie a **Project URL** e a **publishable/anon key**. **Nunca use `service_role` ou `secret` key** no Flutter.

### 3. Configurar secrets do repositório NOVO
`Settings > Secrets and variables > Actions > New repository secret`:
- `SUPABASE_URL`: URL do projeto Supabase.
- `SUPABASE_ANON_KEY`: chave pública publishable/anon do Supabase.

### 4. Publicar Web
1. No GitHub, `Settings > Pages > Build and deployment > Source`: selecione **GitHub Actions**.
2. `Actions > Publicar Conferidor Web > Run workflow` (branch `main`).
3. Aguarde a conclusão. Abra `https://SEU_USUARIO.github.io/conferidor-web/` (substitua pelo endereço real mostrado no workflow).
4. Se o repositório for privado, verifique se sua conta/plano permite publicar GitHub Pages; em alguns planos, Pages para repositório privado não está disponível. Alternativa: Cloudflare Pages ou Firebase Hosting.
5. No Supabase, em `Authentication > URL Configuration`, ajuste `Site URL` para a URL publicada e adicione a mesma URL em `Redirect URLs` para confirmação de cadastro.

### 5. Teste com duas pessoas
1. Pessoa A: criar conta, confirmar e-mail e entrar; criar grupo `Família`.
2. Pessoa A: `Ver convite`, copiar código e enviar à Pessoa B por mensagem privada.
3. Pessoa B: criar conta, confirmar e-mail, entrar e usar `Entrar em grupo` com o código.
4. Pessoa A: cadastrar despesa **individual** e outra **compartilhada**.
5. Pessoa B: confirmar que **só enxerga a compartilhada** e pode marcá-la paga; cadastrar individual própria.
6. Pessoa A: confirmar que não vê a individual da Pessoa B.
7. Testar uma compra de R$ 100,00 em 3 parcelas: deve gerar R$ 33,34 + R$ 33,33 + R$ 33,33 em meses sucessivos.

## Segurança
A interface não é a barreira de segurança: o SQL ativa Row Level Security (RLS) e usa políticas de acesso por usuário/grupo. Não desative RLS. Não coloque chaves administrativas em secrets usados no build web. As chaves públicas ficam embutidas no site, como esperado; a proteção vem da autenticação e RLS.

## Nota sobre Flutter
O workflow executa `flutter create --platforms=web .` durante o build, portanto não é necessário subir a pasta `web/` gerada. Caso `flutter analyze` falhe por uma incompatibilidade de SDK, consulte o log da Action e corrija antes de publicar.
