require 'spec_helper'

describe Redis::Document do

  before do
    Redis::Document.instance_variable_set(:@redis, nil)
    Post.instance_variable_set(:@redis, nil)
  end

  describe ".redis" do
    subject { Redis::Document.redis }
    it { should be_a Redis }
  end

  describe ".redis=" do
    it "should set Redis::Document.redis" do
      redis = stub
      Redis::Document.redis = redis
      Redis::Document.redis.should == redis
    end
  end

  context "when included into a class" do

    subject{ Post.new }
    alias_method :post, :subject

    describe ".redis" do
      subject { Post.redis }
      it { should be_a Redis::Namespace }
    end

    describe ".redis=" do
      it "should set Redis::Document.redis" do
        redis = stub
        Post.redis = redis
        Post.redis.should be_a Redis::Namespace
        Post.redis.instance_variable_get(:@redis).should == redis
      end
    end

    describe ".key" do
      subject{ Factory.document }
      it "should" do
        subject.key :color
        subject.new.should respond_to :color
        subject.new.should respond_to :color=
        subject.new.keys.should == [:id, :color]
        subject.keys.should == [:id, :color]
      end

      CLASSES = [Symbol, String, Integer, Float, Time, Array, Hash]
      VALUES  = [:boosh, 'Love', 42, 10.5, Time.now, [:an,'array'], {:a=>'hash'}]
      it "should marshal objects keys" do
        CLASSES.each{|klass| subject.key :"a_#{klass}"}

        instance = subject.new
        CLASSES.zip(VALUES).each{|klass, value|
          instance.send(:"a_#{klass}=", value)
          instance.send(:"a_#{klass}").should be_a klass
          instance.send(:"a_#{klass}").should == value
        }

        instance.save
        instance.reload
        CLASSES.zip(VALUES).each{|klass, value|
          instance.send(:"a_#{klass}").should be_a klass
          instance.send(:"a_#{klass}").should == value
        }

        instance = subject.find(instance)
        CLASSES.zip(VALUES).each{|klass, value|
          instance.send(:"a_#{klass}").should be_a klass
          instance.send(:"a_#{klass}").should == value
        }
      end
    end

    describe ".keys" do
      it "should return an array of the documents keys" do
        Post.keys.to_set.should == Set[:id, :title, :body, :created_at]
      end
    end

    context "and subclassed" do
      subject{ AwesomePost.new }
      describe ".keys" do
        it "should return an array of the documents keys including its ancestors" do
          AwesomePost.keys.to_set.should == Set[:id, :title, :body, :created_at, :animated_gif]
        end
      end
    end

    describe ".find" do
      it "should return nil when not finding" do
        Post.find(nil).should be_nil
        Post.find('231f1a2a3').should be_nil
        Post.find(214343).should be_nil
        Post.find(Post.new.save.id).should be_a Post
      end
    end

    describe ".new" do
      it "should not try and load if it generates and id" do
        Post.new.inspect
        log.should == ""
      end
    end

    describe "#inspect" do
      subject { Post.new.inspect }
      it { should be_a String }
    end

    describe "#new_record?" do
      it "should return true if our key exists in redis" do
        post = Post.new
        post.new_record?.should be_true
        post.title = 'My Second Post'
        post.new_record?.should be_true
        post.save
        post.new_record?.should be_false
      end
    end

    it "should store all of its data in a single redis hash" do
      post.id.should be_nil
      post.new_record?.should be_true

      post.title = 'My First Post'
      post.title.should == 'My First Post'
      post.get_key(:title).should == 'My First Post'
      post.new_record?.should be_true
      post.save
      post.new_record?.should be_false

      Post.find(post.id).title.should == 'My First Post'
    end

    describe "#reload" do
      it "should values from" do
        post1 = Post.new
        post1.title = 'zomg'
        post1.save

        post2 = Post.find(post1.id)
        post2.title.should == 'zomg'
        post2.title = 'boosh'
        post2.save

        post1.title.should == 'zomg'
        post1.reload
        post1.title.should == 'boosh'
      end
      it "should not make a request to redis if its a new record" do
        post.should_not_receive(:redis)
        post.reload
      end
    end

    describe "#destroy" do
      it "should destroy the redis has" do
        post.title = "a crappy post"
        post.save
        Redis::Document.redis.keys.length.should == post.keys.size
        post.destroy
        Redis::Document.redis.keys.length.should == 0
        post.new_record?.should be_true
      end
    end

    pending "should log to Redis::Document.logger" do
      post = Post.new
      log_lines.should be_empty

      post.new_record?
      log_lines.length.should == 1
      log_lines.first.should include "Post(#{post.id}) exists?"

      empty_log!
      post.title = "my first post"
      log_lines.length.should == 1
      log_lines.first.should include "Post(#{post.id}) write :title"

      empty_log!
      Post.find(post.id)
      log_lines.length.should == 2
      log_lines.last.should include "Post(#{post.id}) find"
    end

  end

end
