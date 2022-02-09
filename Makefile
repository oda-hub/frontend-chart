upgrade:
	bash make.sh upgrade

upgrade-wait:
	bash make.sh upgrade --wait


create-secrets:
	bash make.sh create-secrets

db:
	echo "do bash make.sh db, but it takes a while"


forward:
	bash make.sh forward


container:
	bash make.sh clone_container || echo "can not clone"
	make -B -C frontend-container update build push


update-container-rev:
	(cd frontend-container; git rev-parse HEAD) > frontend_container_revision.txt


update: update-container-rev container
