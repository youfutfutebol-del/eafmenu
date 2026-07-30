
-- Bucket público para fotos de produtos
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('produtos-imagens', 'produtos-imagens', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- Leitura pública (qualquer um vê as fotos, inclusive clientes não logados no PWA)
create policy "Leitura publica de imagens de produtos"
on storage.objects for select
using (bucket_id = 'produtos-imagens');

-- Upload: só usuários autenticados, e o caminho do arquivo deve começar com o tenant_id deles
-- Convenção de path: {tenant_id}/{product_id}.ext
create policy "Equipe do tenant pode enviar imagens"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'produtos-imagens'
  and (storage.foldername(name))[1] = (
    select tenant_id::text from public.profiles where id = auth.uid()
  )
);

-- Update: mesmo critério
create policy "Equipe do tenant pode atualizar imagens"
on storage.objects for update
to authenticated
using (
  bucket_id = 'produtos-imagens'
  and (storage.foldername(name))[1] = (
    select tenant_id::text from public.profiles where id = auth.uid()
  )
);

-- Delete: mesmo critério
create policy "Equipe do tenant pode excluir imagens"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'produtos-imagens'
  and (storage.foldername(name))[1] = (
    select tenant_id::text from public.profiles where id = auth.uid()
  )
);
