DELIMITER $
create procedure prc_verifica_preco (
	in new_cnpj varchar(14),
	in tipo_comb int,
	in valor_novo double(10, 2)
)
begin
	declare new_id_posto int;
	declare new_id_combustivel int;
	declare valor_atual double(10, 2);
	declare contador int;
	select id_posto into new_id_posto from tbl_posto
	where cnpj = new_cnpj;
	select id_combustivel into new_id_combustivel from tbl_tipo_combustivel
	where id_combustivel = tipo_comb;
	select valor into valor_atual from tbl_preco
	where fk_id_posto = new_id_posto and fk_id_combustivel = new_id_combustivel;
	select count(*) into contador from tbl_preco
	where fk_id_posto = new_id_posto and fk_id_combustivel = new_id_combustivel;
	if contador < 1 then
			insert into tbl_preco(fk_id_posto, fk_id_combustivel, valor) 
			values (new_id_posto, new_id_combustivel, valor_novo);
	else
		if valor_atual <> valor_novo then
			insert into tbl_historico_preco (fk_id_posto, fk_id_combustivel, ultimo_valor, dt_atualizacao ) 
			values (new_id_posto, new_id_combustivel, valor_atual, current_timestamp() );
			update tbl_preco set valor = valor_novo
			where fk_id_posto = new_id_posto and fk_id_combustivel = new_id_combustivel;
		end if;
	end if ;
end $
DELIMITER ;

DELIMITER $
create procedure InserirPostoELocalizacao(
	in latitude decimal(10, 6), 
	in longitude decimal(10, 6), 
	in idPosto int, 
	out msg varchar(100)
)
begin
	declare novo_posto_id int;
	if not exists (select 1 from tbl_localizacao_posto where lat = latitude and lon = longitude) then
		if idPosto = 0 then
			insert into tbl_posto (CNPJ) values (0);
			set novo_posto_id = LAST_INSERT_ID();
			insert into tbl_localizacao_posto (fk_id_posto, lat, lon) values (novo_posto_id, latitude, longitude);
		else
			set msg = "essa mensagem não deveria aparecer!";
			if exists (select 1 from tbl_posto where id_posto = idPosto) then
				insert into tbl_localizacao_posto (fk_id_posto, lat, lon) values (idPosto, latitude, longitude);
				if (select ROW_COUNT()) = 0 then
					SIGNAL SQLSTATE '45000' set MESSAGE_TEXT = 'Não foi possível inserir os dados';
				end if;
			else
				set msg = "O posto referenciado não existe";
				SIGNAL SQLSTATE '45000' set MESSAGE_TEXT = "O posto referenciado não existe";
			end if;
		end if;
	else
		set msg = "Já existem dados cadastrados para essa localização";
		SIGNAL SQLSTATE '45000' set MESSAGE_TEXT = "Já existem dados cadastrados para essa localização";
	end if;
end $
DELIMITER ;

DELIMITER $
create procedure pr_avaliacao(
	in usuario int,
	in posto int,
	in avaliacao_posto int,
	in avaliacao_produto int,
	in avaliacao_atendimento int,
	in opiniao_usuario varchar(500),
	out msg varchar(100)
)
begin
	declare m_pos double;
	declare m_pro double;
	declare m_ate double;
	set m_pos = 0;
	set m_pro = 0;
	set m_ate = 0;
	if avaliacao_posto >= 0 and avaliacao_posto <= 5 
	and avaliacao_produto >= 0 and avaliacao_produto <= 5 
	and avaliacao_atendimento >= 0 and avaliacao_atendimento <= 5 then
		if exists (select 1 from tbl_usuario where id_usuario = usuario) then
			if exists (select 1 from tbl_localizacao_posto where id_tlc = posto) then
				if exists (select 1 from tbl_avaliacao where fk_id_tlc = posto and fk_id_usuario = usuario and (av_posto <> avaliacao_posto OR qualidade_prod <> avaliacao_produto OR qualidade_atendimento <> avaliacao_atendimento)) then
					UPDATE tbl_avaliacao
					set av_posto = avaliacao_posto, 
					qualidade_prod = avaliacao_produto,
					qualidade_atendimento = avaliacao_atendimento,
					dt_ava = CURDATE()
					where fk_id_tlc = posto and fk_id_usuario = usuario;
					if (select ROW_COUNT()) = 0 then
						SIGNAL SQLSTATE '45000' set MESSAGE_TEXT = 'Erro ao atualizar os dados de avaliação';
					end if;
					set msg = "avaliação atualizada";
				else
					insert into tbl_avaliacao(av_posto, qualidade_prod, qualidade_atendimento, dt_ava, fk_id_tlc, fk_id_usuario)
					values (avaliacao_posto, avaliacao_produto, avaliacao_atendimento, CURDATE(), posto, usuario);
					if (select ROW_COUNT()) = 0 then
						SIGNAL SQLSTATE '45000' set MESSAGE_TEXT = 'Erro ao inserir os dados de avaliação';
					end if;
					set msg = "avaliação inserida";
				end if;
				select avg(coalesce(qualidade_prod, -1)) as m_pro,
						avg(coalesce(qualidade_atendimento, -1)) as m_ate,
						avg(coalesce(av_posto, -1)) as m_pos
					into m_pro, m_ate, m_pos
					from tbl_avaliacao;
				UPDATE tbl_localizacao_posto
					set media_ava_atendimento = m_ate,
					media_ava_posto = m_pos,
					media_ava_produto = m_pro
				where id_tlc = posto;
				
				if opiniao_usuario IS NOT NULL and opiniao_usuario != "" then
					if exists (select 1 from tbl_comentario where fk_id_tlc = posto and fk_id_usuario = usuario and comentario <> opiniao_usuario) then
						UPDATE tbl_comentario
						set comentario = opiniao_usuario, 
						dt_comentario = CURDATE()
						where fk_id_tlc = posto and fk_id_usuario = usuario;
						if (select ROW_COUNT()) = 0 then
							SIGNAL SQLSTATE '45000' set MESSAGE_TEXT = 'Erro ao atualizar o comentario';
						end if;
					else
						insert into tbl_comentario(comentario, dt_comentario, fk_id_tlc, fk_id_usuario)
						values (opiniao_usuario, CURDATE(), posto, usuario);
						if (select ROW_COUNT()) = 0 then
							SIGNAL SQLSTATE '45000' set MESSAGE_TEXT = 'Erro ao inserir o comentario';
						end if;
					end if;
				end if;
			else
				set msg = "posto inexistente";
				SIGNAL SQLSTATE '23000' set MESSAGE_TEXT = 'Erro ao inserir na tabela de avaliação, posto inexistente';
			end if;
		else
			set msg = "usuario inexistente";
			SIGNAL SQLSTATE '23000' set MESSAGE_TEXT = 'Erro ao inserir na tabela de avaliação, usuario inexistente';
		end if;
	else
		set msg = "valores de avaliacao fora do escopo";
	end if;
end $
DELIMITER ;