Sequel.migration do
	up do
		create_table(:users) do
			primary_key :id
			String :nickserv
		end
		create_table(:messages) do
			primary_key :id
			DateTime :time
			String :text
			String :nick
			foreign_key :user, :users
		end
		create_table(:quotes) do
			primary_key :id
			foreign_key :message, :messages
		end
		create_table(:mails) do
			primary_key :id
			foreign_key :to, :users
			foreign_key :from, :users
			String :text
		end
		create_table(:muted) do
			primary_key :id
			String :forumname
		end
		
	end

	down do
		drop_table(:users)
		drop_table(:nicks)
		drop_table(:messages)
		drop_table(:quotes)
		drop_table(:mails)
		drop_table(:muted)
	end
end
