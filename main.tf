# vault connection and token should be set in the environment variables VAULT_ADDR and VAULT_TOKEN respectively

provider "vault" {

}

# Mount the database secret engine
resource "vault_mount" "database" {
  path        = "db"
  type        = "database"
  description = "database secret engine mount"
}

#setup mysql instance:https://docs.rackspace.com/docs/install-mysql-server-on-the-ubuntu-operating-system
#setup mysql root user: https://dev.mysql.com/doc/refman/5.7/en/resetting-permissions.html
#create mysql admin user that will be used by vault: https://tecadmin.net/how-to-create-a-superuser-in-mysql/

#it is not recommended to manage vault_database_secret_backend_connection using terraform as it will expose the password in the tf file. It is OK for demo purposes.check "name" {

resource "vault_database_secret_backend_connection" "devbox_mysql" {
  backend       = vault_mount.database.path
  name          = "devbox_mysql"
  allowed_roles = ["*"]

  mysql {
    connection_url = "{{username}}:{{password}}@tcp(devbox:3306)/"
    username=  "admin"
  password =  "the_secure_password"
  }
}

locals {
  # Take a directory of YAML files, read each one that matches naming pattern and bring them in to Terraform's native data set
  inputdbrolevars = [for f in fileset(path.module, "database_roles/{db_role_}*.yaml") : yamldecode(file(f))]
  # Take that data set and format it so that it can be used with the for_each command by converting it to a map where each top level key is a unique identifier.
  # In this case I am using the rolename key from my example YAML files
  inputdbrolemap = { for dbrole in toset(local.inputdbrolevars) : dbrole.rolename => dbrole }
}

resource "vault_database_secret_backend_role" "db_roles" {
  for_each = local.inputdbrolemap
  backend             = vault_mount.database.path
  name                = "${vault_database_secret_backend_connection.devbox_mysql.name}_${each.value.rolename}"
  db_name             = vault_database_secret_backend_connection.devbox_mysql.name
  creation_statements = ["CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT ${each.value.priviledges} TO '{{name}}'@'%'; "]
  # revocation_statements = default revocation statements works well for mysql.
  default_ttl = each.value.default_ttl
  max_ttl = each.value.max_ttl
}