web: bin/rails server -p ${PORT:-3000} -e ${RAILS_ENV:-production}
worker: bin/rails solid_queue:start
release: bundle exec rails db:migrate
