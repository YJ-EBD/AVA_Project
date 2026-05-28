alter table if exists ava_ai_knowledge_items
	add column if not exists embedding_model varchar(120);

alter table if exists ava_ai_knowledge_items
	add column if not exists embedding_vector text;

create index if not exists idx_ava_ai_knowledge_embedding_lookup
	on ava_ai_knowledge_items (company_name, embedding_model)
	where embedding_vector is not null;
