//
//  CSFFMpegInput.m
//  CSFFMpegCapturePlugin
//
//  Created by Zakk on 6/11/16.
//  Copyright © 2016 Zakk. All rights reserved.
//

#import "CSFFMpegInput.h"

@implementation CSFFMpegInput


-(instancetype) init
{
    if (self = [super init])
    {
        _video_codec = NULL;
        _video_codec_ctx = NULL;
        _video_stream_idx = -1;
        _audio_stream_idx = -1;
        _is_ready = NO;
        _is_draining = NO;

        _first_video_pts = 0;
        _first_audio_pts = 0;
        _duration = 0.0f;
        _seek_request = NO;
        _seek_time = 0;
        
        _seek_queue = dispatch_queue_create("SEEK QUEUE", DISPATCH_QUEUE_SERIAL);
        
    }
    return self;
}

-(instancetype) initWithMediaPath:(NSString *)mediaPath
{
    if (self = [self init])
    {
        self.mediaPath = mediaPath;
        self.shortName = [mediaPath lastPathComponent];
    }
    
    return self;
}

-(bool)openMedia:(int)bufferVideoFrames
{
    

    if (!self.mediaPath)
    {
        return NO;
    }

    
    if (!_video_message_queue)
    {
        av_thread_message_queue_alloc(&_video_message_queue, 300, sizeof(struct frame_message));
    }
    
    if (!_audio_message_queue)
    {
        av_thread_message_queue_alloc(&_audio_message_queue, 4096 , sizeof(struct frame_message));
    }
    
    av_thread_message_queue_set_err_recv(_video_message_queue, 0);
    av_thread_message_queue_set_err_recv(_audio_message_queue, 0);
    av_thread_message_queue_set_err_send(_video_message_queue, 0);
    av_thread_message_queue_set_err_send(_audio_message_queue, 0);


    


    
    
        AVCodecContext *v_codec_ctx_orig = NULL;
        AVCodecContext *a_codec_ctx_orig = NULL;
        int open_ret = avformat_open_input(&_format_ctx, self.mediaPath.UTF8String, NULL, NULL);
    if (open_ret < 0)
    {
        return NO;
    }
    
    
        avformat_find_stream_info(_format_ctx, NULL);
        //av_dump_format(_format_ctx, 0, self.mediaPath.UTF8String, 0);
        for (int i=0; i < _format_ctx->nb_streams; i++)
        {
            if (_format_ctx->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO && _video_stream_idx == -1)
            {
                _video_stream_idx = i;
            }
            
            if (_format_ctx->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO && _audio_stream_idx == -1)
            {
                _audio_stream_idx = i;
            }
            
            if (_audio_stream_idx > -1 && _video_stream_idx > -1)
            {
                break;
            }
        }
        if (_video_stream_idx > -1)
        {
            self.videoTimeBase = _format_ctx->streams[_video_stream_idx]->time_base;
            v_codec_ctx_orig = _format_ctx->streams[_video_stream_idx]->codec;
            _video_codec = avcodec_find_decoder(v_codec_ctx_orig->codec_id);
            _video_codec_ctx = avcodec_alloc_context3(_video_codec);
            avcodec_copy_context(_video_codec_ctx, v_codec_ctx_orig);
            avcodec_open2(_video_codec_ctx, _video_codec, NULL);
            self.dimensions = NSMakeSize(_video_codec_ctx->width, _video_codec_ctx->height);
            _sws_ctx = sws_alloc_context();
            av_set_int(_sws_ctx, "srcw", _video_codec_ctx->width);
            av_set_int(_sws_ctx, "srch", _video_codec_ctx->height);
            av_set_int(_sws_ctx, "src_format", _video_codec_ctx->pix_fmt);
            av_set_int(_sws_ctx, "dstw", _video_codec_ctx->width);
            av_set_int(_sws_ctx, "dsth", _video_codec_ctx->height);
            av_set_int(_sws_ctx, "dst_format", AV_PIX_FMT_NV12);
            sws_init_context(_sws_ctx, NULL, NULL);
        }
        if (_audio_stream_idx > -1)
        {
            self.audioTimeBase = _format_ctx->streams[_audio_stream_idx]->time_base;

            a_codec_ctx_orig = _format_ctx->streams[_audio_stream_idx]->codec;
            _audio_codec = avcodec_find_decoder(a_codec_ctx_orig->codec_id);
            _audio_codec_ctx = avcodec_alloc_context3(_audio_codec);
            avcodec_copy_context(_audio_codec_ctx, a_codec_ctx_orig);
            avcodec_open2(_audio_codec_ctx, _audio_codec, NULL);
        }
    
    
    self.is_ready = NO;
    _stop_request = NO;
    self.is_draining = NO;
    _video_done = NO;
    _audio_done = NO;
    

    self.duration = _format_ctx->duration / (double)AV_TIME_BASE;
    
    
    

    
        [self readAndDecodeVideoFrames:bufferVideoFrames];
        
     return YES;
}








-(CAMultiAudioPCM *)consumeAudioFrame:(AudioStreamBasicDescription *)asbd error_out:(int *)error_out
{
    struct frame_message msg;
    
    AudioBufferList *sampleABL = NULL;
    int av_ret = 0;
    
    if (_audio_message_queue && ((*error_out = av_thread_message_queue_recv(_audio_message_queue, &msg, AV_THREAD_MESSAGE_NONBLOCK)) >= 0))
    {
        
        AVFrame *recv_frame;
        
        recv_frame = msg.frame;
        if (!recv_frame)
        {
            return NULL;
        }
        
        
        if (recv_frame->width == 999)
        {
            //flush PCM player
            av_frame_free(&recv_frame);
            CAMultiAudioPCM *flushPCM = [[CAMultiAudioPCM alloc] init];
            flushPCM.frameCount = -1;
            flushPCM.bufferCount = -1;
            return flushPCM;
        }
        
            uint8_t **dst_data = NULL;
            int dst_linesize;
            
            if (!_swr_ctx)
            {
                uint64_t channel_layout = _audio_codec_ctx->channel_layout;
                if (!channel_layout)
                {
                    channel_layout = av_get_default_channel_layout(_audio_codec_ctx->channels);
                }
                _swr_ctx = swr_alloc_set_opts(NULL, AV_CH_LAYOUT_STEREO, AV_SAMPLE_FMT_FLTP, asbd->mSampleRate, channel_layout, _audio_codec_ctx->sample_fmt, _audio_codec_ctx->sample_rate, 0, NULL);
                swr_init(_swr_ctx);
            }
            
            
            int dst_nb_samples = av_rescale_rnd(recv_frame->nb_samples, asbd->mSampleRate, _audio_codec_ctx->sample_rate, AV_ROUND_UP);
            av_samples_alloc_array_and_samples(&dst_data, &dst_linesize, 2, dst_nb_samples, AV_SAMPLE_FMT_FLTP, 1);
            int conv_samples = swr_convert(_swr_ctx, dst_data, dst_nb_samples, recv_frame->extended_data, recv_frame->nb_samples);
            
            
            
            
            
            int bufferCnt = asbd->mFormatFlags & kAudioFormatFlagIsNonInterleaved ? asbd->mChannelsPerFrame : 1;
            
            int channelCnt = _audio_codec_ctx->channels;
            
            long byteCnt = asbd->mBytesPerFrame * dst_nb_samples;
            
            sampleABL = malloc(sizeof(AudioBufferList) + (bufferCnt-1)*sizeof(AudioBuffer));
            
            
            sampleABL->mNumberBuffers = bufferCnt;
            
            for (int i=0; i<bufferCnt; i++)
            {
                sampleABL->mBuffers[i].mData = dst_data[i];
                
                sampleABL->mBuffers[i].mDataByteSize = (UInt32)dst_linesize;
                sampleABL->mBuffers[i].mNumberChannels = 1;
            }
        

        
        av_frame_free(&recv_frame);

        CAMultiAudioPCM *retPCM = [[CAMultiAudioPCM alloc] initWithAudioBufferList:sampleABL streamFormat:asbd];
        return retPCM;
        
    } else {
        return NULL;
    }
}



-(void)videoFlush:(bool)withEOF
{
    
    struct frame_message msg;
    avcodec_flush_buffers(_video_codec_ctx);
    int flush_cnt = 0;
    if (_video_message_queue)
    {
        while (av_thread_message_queue_recv(_video_message_queue, &msg, AV_THREAD_MESSAGE_NONBLOCK) >= 0)
        {
            if (msg.frame)
            {
                av_frame_free(&msg.frame);
            }
        }
        if (withEOF)
        {
            av_thread_message_queue_set_err_recv(_video_message_queue, AVERROR_EOF);
        }
    }
    
    
}


-(void)audioFlush
{
    
    struct frame_message msg;
    int flush_cnt = 0;
    
    avcodec_flush_buffers(_audio_codec_ctx);
    if (_audio_message_queue)
    {
        while (av_thread_message_queue_recv(_audio_message_queue, &msg, AV_THREAD_MESSAGE_NONBLOCK) >= 0)
        {

            if (msg.frame)
            {
                av_frame_free(&msg.frame);
            }
        }
        
        AVFrame *flushFrame = av_frame_alloc();
        flushFrame->width = 999;
        msg.frame = flushFrame;
        
        av_thread_message_queue_send(_audio_message_queue, &msg, AV_THREAD_MESSAGE_NONBLOCK);
        
    }
}


-(void)internal_seek:(int64_t)time
{
    if (_format_ctx)
    {
        
        int seek_ret = av_seek_frame(_format_ctx, -1, time, AVSEEK_FLAG_BACKWARD);

        AVFifoBuffer *seek_buffer = av_fifo_alloc(sizeof(AVPacket) * 600);
        
        
        //int seek_ret = avformat_seek_file(_format_ctx, _video_stream_idx, time-10, time, time+10, AVSEEK_FLAG_BACKWARD);
        [self videoFlush:NO];
        [self audioFlush];
        
        AVPacket buf_pkt;
        int64_t video_pts = AV_NOPTS_VALUE;
        
        while (av_read_frame(_format_ctx, &buf_pkt) >= 0)
        {
            if (buf_pkt.stream_index == _video_stream_idx)
            {
                video_pts = buf_pkt.pts;
                [self decodeVideoPacket:&buf_pkt];
                av_free_packet(&buf_pkt);
                break;
            } else if (buf_pkt.stream_index == _audio_stream_idx){
                av_fifo_generic_write(seek_buffer, &buf_pkt, sizeof(AVPacket), NULL);
            }
        }
        
        while (av_fifo_size(seek_buffer) >= sizeof(AVPacket))
        {
            AVPacket a_pkt;
            av_fifo_generic_read(seek_buffer, &a_pkt, sizeof(AVPacket), NULL);
            if (av_compare_ts(a_pkt.pts, self.audioTimeBase, video_pts, self.videoTimeBase) >= 0)
            {
                [self decodeAudioPacket:&a_pkt];
            }
            av_free_packet(&a_pkt);
        }
        av_fifo_free(seek_buffer);
        
        _first_video_pts = 0;
        _seek_request = NO;
    }
}

-(void)seek:(double)time
{
    if (_seek_request) return;
    
    if (_format_ctx)
    {
        int64_t seek_pts = time / av_q2d(AV_TIME_BASE_Q);

        
        _seek_time = seek_pts;
        _seek_request = YES;
        av_thread_message_queue_set_err_send(_video_message_queue, AVERROR_EXTERNAL);

        //[self audioFlush];
    }
    
}

-(void)stop
{
    _stop_request = YES;
}

-(AVFrame *)consumeFrame:(int *)error_out
{
    
    if (!_video_message_queue)
    {
        return NULL;
    }
    
    
    if (_video_done)
    {
        return NULL;
    }
    *error_out = 0;
    
    struct frame_message msg;
    AVFrame *recv_frame;
    if ((*error_out = av_thread_message_queue_recv(_video_message_queue, &msg, AV_THREAD_MESSAGE_NONBLOCK)) >= 0)
    {
        recv_frame = msg.frame;
    } else {
        if (*error_out == AVERROR_EOF)
        {
            _video_done = YES;
        }
        
        if (self.is_draining)
        {
            self.is_ready = NO;
        }
        recv_frame = NULL;
    }
    return recv_frame;
}


//You should run this is a gcd queue/block

-(void)readAndDecodeVideoFrames:(int)frameCnt
{
    
    int read_frames = 0;
    AVFrame *output_frame = NULL;
    AVPacket av_packet;
    bool do_audio = YES;
    bool do_video = YES;
    int64_t seek_pts;
    struct frame_message msg;
    
    
    
    if (!_format_ctx)
    {
        return;
    }
    
    
    int pkt_cnt = 0;
    
    while (do_audio || do_video)
    {
        if (_stop_request)
        {
            [self closeMedia];
            _stop_request = NO;
            return;
        }
        
        if (_seek_request)
        {
            [self internal_seek:_seek_time];
            av_thread_message_queue_set_err_send(_video_message_queue, 0);
            
        }
        
        
        if (frameCnt == 0 && !self.is_ready)
        {
            
            continue;
        }
        
        output_frame = av_frame_alloc();
        int got_decoded_frame;
        int read_ret = 0;
        
        if (!self.is_draining)
        {
            read_ret = av_read_frame(_format_ctx, &av_packet);
        } else {
            
            if (do_video)
            {
                av_init_packet(&av_packet);
                av_packet.stream_index = _video_stream_idx;
                av_packet.size = 0;
                av_packet.data = NULL;
                
            } else if (do_audio) {
                av_init_packet(&av_packet);
                av_packet.stream_index = _audio_stream_idx;
                av_packet.size = 0;
                av_packet.data = NULL;
            }
        }
        
        if (read_ret < 0)
        {
            self.is_draining = YES;
            continue;
        }
        
        
        
        if (do_video && (av_packet.stream_index == _video_stream_idx))
        {
            
            if (_first_video_pts == 0 && av_packet.pts != AV_NOPTS_VALUE)
            {
                _first_video_pts = av_packet.pts;
            }
            
            bool got_frame = [self decodeVideoPacket:&av_packet];
            
            
            
            if (!got_frame)
            {
                if (self.is_draining)
                {
                    av_thread_message_queue_set_err_recv(_video_message_queue, AVERROR_EOF);
                    do_video = NO;
                }
            } else {
                read_frames++;
            }
        } else if (do_audio && (av_packet.stream_index == _audio_stream_idx)) {
            
            if (_first_audio_pts == 0)
            {
                _first_audio_pts = av_packet.pts;
            }
            
            bool got_frame = [self decodeAudioPacket:&av_packet];
            if (!got_frame && self.is_draining)
            {
                do_audio = NO;
                av_thread_message_queue_set_err_recv(_audio_message_queue, AVERROR_EOF);
            }
        }
        av_free_packet(&av_packet);

        av_frame_free(&output_frame);
        if (frameCnt > 0 && read_frames >= frameCnt && !self.is_ready)
        {
            self.is_ready = YES;
            return;
        }
        
    }
}


-(bool)decodeAudioPacket:(AVPacket *)av_packet
{
    
    AVFrame *output_frame = NULL;
    void *orig_data;
    size_t orig_size;
    orig_size = av_packet->size;
    orig_data = av_packet->data;
    bool ret = NO;
    int got_decoded_frame = 0;
    output_frame = av_frame_alloc();
    struct frame_message msg;
    
    
    int read_len;
    while (av_packet->size > 0 || av_packet->data == NULL)
    {
        
        read_len = avcodec_decode_audio4(_audio_codec_ctx, output_frame, &got_decoded_frame, av_packet);
        if (got_decoded_frame)
        {
            if (!output_frame->channel_layout)
            {
                output_frame->channel_layout = av_get_default_channel_layout(_audio_codec_ctx->channels);
            }
            AVFrame *cloned_frame = av_frame_clone(output_frame);
            
            msg.frame = cloned_frame;
            msg.notused = 0;
            av_thread_message_queue_send(_audio_message_queue, &msg, 0);
            ret = YES;
            
        } else {
            if (self.is_draining)
            {
                ret = NO;
                break;
            }
        }
        if (!self.is_draining)
        {
            if (read_len < 0)
            {
                av_packet->data = orig_data;
                av_packet->size = orig_size;
                break;
            } else {
                av_packet->data += read_len;
                av_packet->size -= read_len;
            }
        }
    }
    av_frame_free(&output_frame);
    return ret;
}


-(bool)decodeVideoPacket:(AVPacket *)av_packet
{
    AVFrame *output_frame = NULL;
    struct frame_message msg;
    int got_decoded_frame = 0;
    bool ret = NO;
    

    
    
    output_frame = av_frame_alloc();

    avcodec_decode_video2(_video_codec_ctx, output_frame, &got_decoded_frame, av_packet);
    if (got_decoded_frame)
    {

        int width = output_frame->width;
        int height = output_frame->height;
        
        
        
        AVFrame* conv_frame = avcodec_alloc_frame();
        conv_frame->width = width;
        conv_frame->height = height;
        conv_frame->format = AV_PIX_FMT_NV12;
        
        int num_bytes = avpicture_get_size(AV_PIX_FMT_NV12, width, height);
        uint8_t* conv_buffer = (uint8_t *)av_malloc(num_bytes);
        avpicture_fill((AVPicture*)conv_frame, conv_buffer, AV_PIX_FMT_NV12, width, height);
        int scale_ret = sws_scale(_sws_ctx, output_frame->data, output_frame->linesize, 0, height, conv_frame->data, conv_frame->linesize);
        conv_frame->pts = output_frame->pts;
        conv_frame->pkt_dts = output_frame->pkt_dts;
        if (output_frame->pkt_pts != AV_NOPTS_VALUE)
        {
            
            conv_frame->pkt_pts = output_frame->pkt_pts;
        } else {
            conv_frame->pkt_pts = output_frame->pkt_dts; //I guess
        }
        
        
        msg.frame = conv_frame;
        msg.notused = 0;
        av_thread_message_queue_send(_video_message_queue, &msg, 0);
        ret = YES;
    } else {
        ret = NO;
    }
    av_frame_free(&output_frame);

    return ret;
}


-(void) closeMedia
{
    
    struct frame_message msg;

    if (_video_message_queue)
    {
        while (av_thread_message_queue_recv(_video_message_queue, &msg, AV_THREAD_MESSAGE_NONBLOCK) >= 0)
        {
            if (msg.frame)
            {
                av_frame_free(&msg.frame);
            }
        }
        
        av_thread_message_queue_set_err_recv(_video_message_queue, AVERROR_EOF);

    }
    
    if (_audio_message_queue)
    {
        av_thread_message_queue_set_err_recv(_audio_message_queue, AVERROR_EOF);

        
        while (av_thread_message_queue_recv(_audio_message_queue, &msg, AV_THREAD_MESSAGE_NONBLOCK) >= 0)
        {
            if (msg.frame)
            {
                av_frame_free(&msg.frame);
            }
        }

    }
    
    if (_video_codec_ctx)
    {
        avcodec_close(_video_codec_ctx);
    }
    
    if (_audio_codec_ctx)
    {
        avcodec_close(_audio_codec_ctx);
    }

    
    if (_format_ctx)
    {
        avformat_close_input(&_format_ctx);
    }
    
    _video_codec_ctx = NULL;
    _audio_codec_ctx = NULL;

    _format_ctx = NULL;
    if (_sws_ctx)
    {
        sws_freeContext(_sws_ctx);
        _sws_ctx = NULL;
    }
    
    if (_swr_ctx)
    {
        swr_free(&_swr_ctx);
    }


    self.duration = 0.0f;
    
 
}

-(void)dealloc
{
    NSLog(@"DEALLOC?");
    [self closeMedia];
    if (_video_message_queue)
    {
        av_thread_message_queue_free(&_video_message_queue);
        _video_message_queue = NULL;
    }
    
    if (_audio_message_queue)
    {
        av_thread_message_queue_free(&_audio_message_queue);
        _audio_message_queue = NULL;

    }
}

@end
